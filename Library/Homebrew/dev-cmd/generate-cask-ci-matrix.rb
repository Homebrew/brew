# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "tap"
require "utils/github/api"
require "cli/parser"
require "system_command"

module Homebrew
  module DevCmd
    class GenerateCaskCiMatrix < AbstractCommand
      MAX_JOBS = 256

      # Weight for each arch must add up to 1.0.
      X86_MACOS_RUNNERS = T.let({
        { symbol: :sequoia, name: "macos-15-intel", arch: :intel } => 1.0,
      }.freeze, T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      X86_LINUX_RUNNERS = T.let({
        { symbol: :linux, name: "ubuntu-22.04", arch: :intel } => 1.0,
      }.freeze, T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      ARM_MACOS_RUNNERS = T.let({
        { symbol: :sonoma,  name: "macos-14", arch: :arm } => 0.0,
        { symbol: :sequoia, name: "macos-15", arch: :arm } => 0.0,
        { symbol: :tahoe,   name: "macos-26", arch: :arm } => 1.0,
      }.freeze, T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      ARM_LINUX_RUNNERS = T.let({
        { symbol: :linux, name: "ubuntu-22.04-arm", arch: :arm } => 1.0,
      }.freeze, T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      MACOS_RUNNERS = T.let(X86_MACOS_RUNNERS.merge(ARM_MACOS_RUNNERS).freeze,
                            T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      LINUX_RUNNERS = T.let(X86_LINUX_RUNNERS.merge(ARM_LINUX_RUNNERS).freeze,
                            T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])
      RUNNERS = T.let(MACOS_RUNNERS.merge(LINUX_RUNNERS).freeze,
                      T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float])

      cmd_args do
        description <<~EOS
          Generate a GitHub Actions matrix for a given pull request URL or list of cask names.
          For internal use in Homebrew taps.
        EOS
        switch "--url",
               description: "Treat named argument as a pull request URL."
        switch "--cask", "--casks",
               description: "Treat all named arguments as cask tokens."
        switch "--skip-install",
               description: "Skip installing casks."
        switch "--new",
               description: "Run new cask checks."
        switch "--syntax-only",
               description: "Only run syntax checks."

        conflicts "--url", "--cask"
        conflicts "--syntax-only", "--skip-install"
        conflicts "--syntax-only", "--new"

        named_args [:cask, :url], min: 0

        hide_from_man_page!
      end

      sig { override.void }
      def run
        skip_install = args.skip_install?
        new_cask = args.new?
        casks = args.named if args.casks?
        pr_url = args.named if args.url?
        syntax_only = args.syntax_only?

        repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        raise UsageError, "The `$GITHUB_REPOSITORY` environment variable must be set." if repository.blank?

        tap = T.let(Tap.fetch(repository), Tap)

        unless syntax_only
          raise UsageError, "Either `--cask` or `--url` must be specified." if !args.casks? && !args.url?
          raise UsageError, "Please provide a `--cask` or `--url` argument." if casks.blank? && pr_url.blank?
        end
        raise UsageError, "Only one `--url` can be specified." if pr_url&.count&.> 1

        labels = if pr_url && (first_pr_url = pr_url.first)
          pr = GitHub::API.open_rest(first_pr_url)
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

      sig { params(cask: Cask::Cask).returns(T::Hash[T::Hash[Symbol, T.any(Symbol, String)], Float]) }
      def filter_runners(cask)
        filtered_macos_runners = RUNNERS.select do |runner, _|
          runner[:symbol] != :linux &&
            cask.depends_on.macos.present? &&
            cask.depends_on.macos.allows?(MacOSVersion.from_symbol(T.must(runner[:symbol]).to_sym))
        end

        filtered_runners = if filtered_macos_runners.any?
          filtered_macos_runners
        else
          RUNNERS.dup
        end

        filtered_runners = filtered_runners.merge(LINUX_RUNNERS) if cask.supports_linux?

        archs = architectures(cask:)
        filtered_runners.select! do |runner, _|
          archs.include?(runner.fetch(:arch))
        end

        filtered_runners
      end

      sig { params(cask: Cask::Cask).returns(T::Array[Symbol]) }
      def architectures(cask:)
        return RUNNERS.keys.map { |r| r.fetch(:arch).to_sym }.uniq.sort if cask.depends_on.arch.blank?

        cask.depends_on.arch.map { |arch| arch[:type] }.uniq.sort
      end

      sig {
        params(available_runners: T::Hash[T::Hash[Symbol, T.any(Symbol, String)],
                                          Float]).returns(T::Hash[Symbol, T.any(Symbol, String)])
      }
      def random_runner(available_runners = ARM_MACOS_RUNNERS)
        T.must(available_runners.max_by { |(_, weight)| rand ** (1.0 / weight) })
         .first
      end

      sig { params(cask: Cask::Cask).returns([T::Array[T::Hash[Symbol, T.any(Symbol, String)]], T::Boolean]) }
      def runners(cask:)
        filtered_runners = filter_runners(cask)

        filtered_macos_found = filtered_runners.keys.any? do |runner|
          cask.to_hash_with_variations["variations"].key?(T.must(runner[:symbol]).to_sym)
        end

        if filtered_macos_found
          # If the cask varies on a MacOS version, test it on every possible macOS version.
          [filtered_runners.keys, true]
        else
          # Otherwise, select a runner from each architecture based on weighted random sample.
          grouped_runners = filtered_runners.group_by { |runner, _| runner.fetch(:arch) }
          selected_runners = grouped_runners.map do |_, runners|
            random_runner(runners.to_h)
          end
          [selected_runners, false]
        end
      end

      sig {
        params(tap: T.nilable(Tap), labels: T::Array[String], cask_names: T::Array[String], skip_install: T::Boolean,
               new_cask: T::Boolean).returns(T::Array[T::Hash[Symbol,
                                                              T.any(String, T::Boolean, T::Array[String])]])
      }
      def generate_matrix(tap, labels: [], cask_names: [], skip_install: false, new_cask: false)
        odie "This command must be run from inside a tap directory." unless tap

        changed_files = find_changed_files(tap)

        ruby_files_in_wrong_directory =
          T.must(changed_files[:modified_ruby_files]) - (
            T.must(changed_files[:modified_cask_files]) +
            T.must(changed_files[:modified_command_files]) +
            T.must(changed_files[:modified_github_actions_files])
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
          T.must(changed_files[:modified_cask_files])
        end

        jobs = cask_files_to_check.count
        odie "Maximum job matrix size exceeded: #{jobs}/#{MAX_JOBS}" if jobs > MAX_JOBS

        cask_files_to_check.flat_map do |path|
          cask_token = path.basename(".rb")

          audit_args = ["--online", "--signing"]
          audit_args << "--new" if T.must(changed_files[:added_files]).include?(path) || new_cask

          audit_exceptions = []

          audit_exceptions << %w[homepage_https_availability] if labels.include?("ci-skip-homepage")

          if labels.include?("ci-skip-livecheck")
            audit_exceptions << %w[hosting_with_livecheck livecheck_https_availability livecheck_version min_os]
          end

          audit_exceptions << "min_os" if labels.include?("ci-skip-livecheck-min-os")

          if labels.include?("ci-skip-repository")
            audit_exceptions << %w[github_repository github_prerelease_version
                                   gitlab_repository gitlab_prerelease_version
                                   bitbucket_repository]
          end

          audit_exceptions << %w[token_valid token_bad_words] if labels.include?("ci-skip-token")

          audit_args << "--except" << audit_exceptions.join(",") if audit_exceptions.any?

          cask = Cask::CaskLoader.load(path.expand_path)

          runners, multi_os = runners(cask:)
          runners.product(architectures(cask:)).filter_map do |runner, arch|
            native_runner_arch = arch == runner.fetch(:arch)
            # we don't need to run simulated archs on Linux
            next if runner.fetch(:symbol) == :linux && !native_runner_arch
            # we don't need to run simulated archs on macOS
            next if runner.fetch(:symbol) == :sequoia && !native_runner_arch

            # If it's just a single OS test then we can just use the two real arch runners.
            next if !native_runner_arch && !multi_os

            arch_args = native_runner_arch ? [] : ["--arch=#{arch}"]
            runner_output = {
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

            if runner.fetch(:symbol) == :linux
              runner_output[:container] = {
                image:   "ghcr.io/homebrew/ubuntu22.04:main",
                options: "--user=linuxbrew",
              }
            end

            runner_output
          end
        end
      end

      sig { params(tap: Tap).returns(T::Hash[Symbol, T::Array[String]]) }
      def find_changed_files(tap)
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
