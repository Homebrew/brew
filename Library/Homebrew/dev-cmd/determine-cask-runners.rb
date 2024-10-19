# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "tap"
require "utils/github/api"
require "cli/parser"
require "system_command"

module Homebrew
  module DevCmd
    class DetermineCaskRunners < AbstractCommand
      MAX_JOBS = 256

      # Weight for each arch must add up to 1.0.
      INTEL_RUNNERS = T.let({
        { symbol: :monterey, name: "macos-12", arch: :intel } => 0.0,
        { symbol: :ventura,  name: "macos-13", arch: :intel } => 1.0,
      }.freeze, T::Hash[T.untyped, T.untyped])
      ARM_RUNNERS = T.let({
        { symbol: :sonoma,   name: "macos-14", arch: :arm   } => 0.0,
        { symbol: :sequoia, name: "macos-15", arch: :arm }    => 1.0,
      }.freeze, T::Hash[T.untyped, T.untyped])
      RUNNERS = T.let(INTEL_RUNNERS.merge(ARM_RUNNERS).freeze, T::Hash[T.untyped, T.untyped])

      # This string uses regex syntax and is intended to be interpolated into
      # `Regexp` literals, so the backslashes must be escaped to be preserved.
      DEPENDS_ON_MACOS_ARRAY_MEMBER = '\\s*"?:([^\\s",]+)"?,?\\s*'

      cmd_args do
        description <<~EOS
          Generate a GitHub Actions matrix for a given pull request URL or list of cask names.
          For internal use in Homebrew taps.
        EOS

        flag "--url=",
             description: "URL of a pull request to generate a matrix for."
        flag "--tap=",
             description: "The tap."
        switch "--skip-install",
               description: "Skip installing casks"
        switch "--new",
               description: "Run new cask checks"
        switch "--syntax-only",
               description: "Only run syntax checks"

        conflicts "--url", "--casks"
        conflicts "--syntax-only", "--url"
        conflicts "--syntax-only", "--casks"
        conflicts "--syntax-only", "--skip-install"
        conflicts "--syntax-only", "--new"

        named_args [:cask], min: 0
        hide_from_man_page!
      end

      sig { params(args: T.untyped).void }
      def initialize(*args)
        super
        repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        raise UsageError, "The GITHUB_REPOSITORY environment variable must be set." if repository.blank?

        @tap = T.let(Tap.fetch(repository), Tap)
      end

      sig { override.void }
      def run
        skip_install = args.skip_install?
        new_cask = args.new?
        casks = args.named if args.named.any?
        pr_url = args.url
        syntax_only = args.syntax_only?
        tap = @tap

        if casks.blank? && pr_url.blank?
          raise UsageError, "Either a list of cask names or a pull request URL must be provided."
        end

        labels = if pr_url
          pr = GitHub::API.open_rest(pr_url)
          pr.fetch("labels").map { |l| l.fetch("name") }
        else
          []
        end

        runner = random_runner[:name]
        syntax_job = {
          name:   "syntax",
          tap:    tap.name,
          runner:,
        }

        matrix = [syntax_job]

        if !syntax_only && !labels&.include?("ci-syntax-only")
          cask_jobs = if casks&.any?
            generate_matrix(tap, labels:, cask_names: casks, skip_install:, new_cask:)
          else
            generate_matrix(tap, labels:, skip_install:, new_cask:)
          end

          if cask_jobs.any?
            # If casks were changed, skip `audit` for whole tap.
            syntax_job[:skip_audit] = true

            # The syntax job only runs `style` at this point, which should work on Linux.
            # Running on macOS is currently faster though, since `homebrew/cask` and
            # `homebrew/core` are already tapped on macOS CI machines.
            # syntax_job[:runner] = "ubuntu-latest"
          end

          matrix += cask_jobs
        end

        syntax_job[:name] += " (#{syntax_job[:runner]})"

        puts JSON.pretty_generate(matrix)
        github_output = ENV.fetch("GITHUB_OUTPUT", nil)
        return unless github_output

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "matrix=#{JSON.generate(matrix)}"
        end
      end

      sig { params(cask_content: BasicObject).returns(T.untyped) }
      def filter_runners(cask_content)
        # Retrieve arguments from `depends_on macos:`
        required_macos = case cask_content
        when /depends_on\s+macos:\s+\[((?:#{DEPENDS_ON_MACOS_ARRAY_MEMBER})+)\]/o
          Regexp.last_match(1).scan(/#{DEPENDS_ON_MACOS_ARRAY_MEMBER}/o).flatten.map(&:to_sym).map do |v|
            {
              version:    v,
              comparator: "==",
            }
          end
        when /depends_on\s+macos:\s+"?:([^\s"]+)"?/ # e.g. `depends_on macos: :big_sur`
          [
            {
              version:    Regexp.last_match(1).to_sym,
              comparator: "==",
            },
          ]
        when /depends_on\s+macos:\s+"([=<>]=)\s+:([^\s"]+)"/ # e.g. `depends_on macos: ">= :monterey"`
          [
            {
              version:    Regexp.last_match(2).to_sym,
              comparator: Regexp.last_match(1),
            },
          ]
        when /depends_on\s+macos:/
          # In this case, `depends_on macos:` is present but wasn't matched by the
          # previous regexes. We want this to visibly fail so we can address the
          # shortcoming instead of quietly defaulting to `RUNNERS`.
          odie "Unhandled `depends_on macos` argument"
        else
          []
        end

        filtered_runners = RUNNERS.select do |runner, _|
          required_macos.any? do |r|
            MacOSVersion.from_symbol(runner.fetch(:symbol)).compare(
              r.fetch(:comparator),
              MacOSVersion.from_symbol(r.fetch(:version)),
            )
          end
        end
        filtered_runners = RUNNERS.dup if filtered_runners.empty?

        archs = architectures(cask_content:)
        filtered_runners.select! do |runner, _|
          archs.include?(runner.fetch(:arch))
        end

        RUNNERS
      end

      sig { params(cask_content: BasicObject).returns(T.untyped) }
      def architectures(cask_content:)
        case cask_content
        when /depends_on\s+arch:\s+:arm64/
          [:arm]
        when /depends_on\s+arch:\s+:x86_64/
          [:intel]
        when /\barch\b/, /\bon_(arm|intel)\b/
          [:arm, :intel]
        else
          RUNNERS.keys.map { |r| r.fetch(:arch) }.uniq.sort
        end
      end

      sig { params(available_runners: T.untyped).returns(T.untyped) }
      def random_runner(available_runners = ARM_RUNNERS)
        available_runners.max_by { |(_, weight)| rand ** (1.0 / weight) }
                         .first
      end

      sig { params(cask_content: T.untyped).returns(T::Array[T.untyped]) }
      def runners(cask_content:)
        filtered_runners = filter_runners(cask_content)

        macos_version_found = cask_content.match?(/\bMacOS\s*\.version\b/m)
        filtered_macos_found = filtered_runners.keys.any? do |runner|
          (
            macos_version_found &&
            cask_content.include?(runner[:symbol].inspect)
          ) || cask_content.include?("on_#{runner[:symbol]}")
        end

        if filtered_macos_found
          # If the cask varies on a MacOS version, test it on every possible macOS version.
          [filtered_runners.keys, true]
        else
          # Otherwise, select a runner from each architecture based on weighted random sample.
          grouped_runners = filtered_runners.group_by { |runner, _| runner.fetch(:arch) }
          selected_runners = grouped_runners.map do |_, runners|
            random_runner(runners)
          end
          [selected_runners, false]
        end
      end

      sig {
        params(tap: T.untyped, labels: T.untyped, cask_names: T.untyped, skip_install: T.untyped,
               new_cask: T.untyped).returns(T::Array[T.untyped])
      }
      def generate_matrix(tap, labels: [], cask_names: [], skip_install: false, new_cask: false)
        odie "This command must be run from inside a tap directory." unless tap

        changed_files = find_changed_files

        ruby_files_in_wrong_directory =
          changed_files[:modified_ruby_files] - (
          changed_files[:modified_cask_files] +
          changed_files[:modified_command_files] +
          changed_files[:modified_github_actions_files]
        )

        if ruby_files_in_wrong_directory.any?
          ruby_files_in_wrong_directory.each do |path|
            puts "::error file=#{path}::File is in wrong directory."
          end

          odie "Found Ruby files in wrong directory:\n#{ruby_files_in_wrong_directory.join("\n")}"
        end

        cask_files_to_check = if cask_names.any?
          cask_names.map do |cask_name|
            Cask::CaskLoader.find_cask_in_tap(cask_name, tap).relative_path_from(tap.path)
          end
        else
          changed_files[:modified_cask_files]
        end

        jobs = cask_files_to_check.count
        odie "Maximum job matrix size exceeded: #{jobs}/#{MAX_JOBS}" if jobs > MAX_JOBS

        cask_files_to_check.flat_map do |path|
          cask_token = path.basename(".rb")

          audit_args = ["--online"]
          audit_args << "--new" if changed_files[:added_files].include?(path) || new_cask

          audit_args << "--signing"

          audit_exceptions = []

          audit_exceptions << %w[homepage_https_availability] if labels.include?("ci-skip-homepage")

          if labels.include?("ci-skip-livecheck")
            audit_exceptions << %w[hosting_with_livecheck livecheck_https_availability
                                   livecheck_min_os livecheck_version]
          end

          audit_exceptions << "livecheck_min_os" if labels.include?("ci-skip-livecheck-min-os")

          if labels.include?("ci-skip-repository")
            audit_exceptions << %w[github_repository github_prerelease_version
                                   gitlab_repository gitlab_prerelease_version
                                   bitbucket_repository]
          end

          if labels.include?("ci-skip-token")
            audit_exceptions << %w[token_conflicts token_valid
                                   token_bad_words]
          end

          audit_args << "--except" << audit_exceptions.join(",") if audit_exceptions.any?

          cask_content = path.read

          runners, multi_os = runners(cask_content:)
          runners.product(architectures(cask_content:)).filter_map do |runner, arch|
            native_runner_arch = arch == runner.fetch(:arch)
            # If it's just a single OS test then we can just use the two real arch runners.
            next if !native_runner_arch && !multi_os

            arch_args = native_runner_arch ? [] : ["--arch=#{arch}"]
            {
              name:         "test #{cask_token} (#{runner.fetch(:name)}, #{arch})",
              tap:          tap.name,
              cask:         {
                token: cask_token,
                path:  "./#{path}",
              },
              audit_args:   audit_args + arch_args,
              fetch_args:   arch_args,
              skip_install: labels.include?("ci-skip-install") || !native_runner_arch || skip_install,
              runner:       runner.fetch(:name),
            }
          end
        end
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def find_changed_files
        tap = @tap

        commit_range_start = Utils.safe_popen_read("git", "rev-parse", "origin").chomp
        commit_range_end = Utils.safe_popen_read("git", "rev-parse", "HEAD").chomp
        commit_range = "#{commit_range_start}...#{commit_range_end}"

        modified_files = Utils.safe_popen_read("git", "diff", "--name-only", "--diff-filter=AMR", commit_range)
                              .split("\n")
                              .map do |path|
          Pathname(path)
        end

        added_files = Utils.safe_popen_read("git", "diff", "--name-only", "--diff-filter=A", commit_range)
                           .split("\n")
                           .map do |path|
          Pathname(path)
        end

        modified_ruby_files = modified_files.select { |path| path.extname == ".rb" }
        modified_command_files = modified_files.select { |path| path.ascend.to_a.last.to_s == "cmd" }
        modified_github_actions_files = modified_files.select do |path|
          path.to_s.start_with?(".github/actions/")
        end
        modified_cask_files = modified_files.select { |path| tap.cask_file?(path.to_s) }

        {
          modified_files:,
          added_files:,
          modified_ruby_files:,
          modified_command_files:,
          modified_github_actions_files:,
          modified_cask_files:,
        }
      end
    end
  end
end
