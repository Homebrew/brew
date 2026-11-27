# typed: strict
# frozen_string_literal: true

require "utils/github/api"
require "utils/output"

module Cask
  module CI
    # Selects GitHub Actions runners and test-bot options for each changed cask.
    module RunnerMatrix
      extend ::Utils::Output::Mixin

      Runner = T.type_alias { T::Hash[Symbol, T.any(Symbol, String)] }
      MAX_JOBS = 256
      LIVECHECK_AUDITS = %w[hosting_with_livecheck livecheck_https_availability livecheck_version min_os].freeze

      # Weight for each arch must add up to 1.0.
      MACOS_RUNNERS = T.let({
        { symbol: :sequoia,     name: "macos-15", arch: :arm } => 0.0,
        { symbol: :tahoe,       name: "macos-26", arch: :arm } => 0.0,
        { symbol: :golden_gate, name: "xcode-27", arch: :arm } => 1.0,
      }.freeze, T::Hash[Runner, Float])
      LINUX_RUNNERS = T.let({
        { symbol: :linux, name: "ubuntu-latest", arch: :intel }       => 1.0,
        { symbol: :linux, name: OS::LINUX_CI_ARM_RUNNER, arch: :arm } => 1.0,
      }.freeze, T::Hash[Runner, Float])
      RUNNERS = T.let(MACOS_RUNNERS.merge(LINUX_RUNNERS).freeze, T::Hash[Runner, Float])

      sig { params(pr_url: T.nilable(String)).returns(T::Array[String]) }
      def self.labels(pr_url)
        return [] unless pr_url

        GitHub::API.open_rest(pr_url).fetch("labels").map { |label| label.fetch("name") }
      end

      sig { params(count: Integer).void }
      def self.check_size!(count)
        odie "Maximum job matrix size exceeded: #{count}/#{MAX_JOBS}" if count > MAX_JOBS
      end

      sig {
        params(default_tap: Tap, cask_names: T::Array[String], added_casks: T::Array[String], labels: T::Array[String],
               skip_install: T::Boolean, new_cask: T::Boolean)
          .returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean, T::Array[String], T::Hash[Symbol, String])]])
      }
      def self.generate(default_tap, cask_names, added_casks:, labels:, skip_install:, new_cask:)
        require "cask/cask_loader"

        return [] if labels.include?("ci-syntax-only")

        check_size!(cask_names.size)
        skip_install ||= labels.include?("ci-skip-install")
        audit_exceptions = {
          "ci-skip-homepage"         => %w[homepage_https_availability homepage_domain_age],
          "ci-skip-livecheck"        => LIVECHECK_AUDITS,
          "ci-skip-livecheck-min-os" => %w[min_os],
          "ci-skip-repository"       => %w[github_repository github_prerelease_version
                                           gitlab_repository gitlab_prerelease_version
                                           forgejo_repository forgejo_prerelease_version bitbucket_repository],
          "ci-skip-self-submission"  => %w[self_submission],
          "ci-skip-token"            => %w[token_valid token_bad_words token_conflicts],
        }.slice(*labels).values.flatten.uniq
        jobs = cask_names.flat_map do |name|
          tap_name, _, cask_token = name.rpartition("/")
          tap = tap_name.empty? ? default_tap : Tap.fetch(tap_name)
          path = CaskLoader.find_cask_in_tap(cask_token, tap).relative_path_from(tap.path)
          testing_cask = tap.core_cask_tap? ? cask_token : "#{tap.name}/#{cask_token}"

          audit_args = ["--online"]
          added = new_cask || added_casks.include?("#{tap.name}/#{cask_token}") ||
                  (tap == default_tap && added_casks.include?(cask_token))
          audit_args << "--new" if added

          cask = CaskLoader.from_tap_path(tap.path/path)

          runners = runners(cask:)
          puts "::warning file=#{path}::No CI runner supports this cask, so it will not be tested." if runners.empty?

          # `macos-15` intermittently fails `signing` on notarized artifacts that other
          # macOS runners accept, e.g. https://github.com/Homebrew/homebrew-cask/pull/294364,
          # so skip it there when another macOS runner audits the same URL.
          macos_urls = runners.reject { |runner| runner.fetch(:symbol) == :linux }.to_h do |runner|
            tag = ::Utils::Bottles::Tag.new(system: runner.fetch(:symbol).to_sym, arch: runner.fetch(:arch).to_sym)
            [runner.fetch(:symbol), cask.refresh_for_tag(tag) { cask.url.to_s }]
          end
          skip_sequoia_signing = macos_urls.except(:sequoia).value?(macos_urls[:sequoia])

          runners.map do |runner|
            runner_audit_exceptions = audit_exceptions.dup
            runner_audit_exceptions << "signing" if skip_sequoia_signing && runner.fetch(:symbol) == :sequoia
            runner_audit_args = audit_args.dup
            runner_audit_args << "--except" << runner_audit_exceptions.join(",") if runner_audit_exceptions.any?

            test_bot_args = ["--only-casks"]
            test_bot_args << "--skip-install" if skip_install
            if labels.include?("ci-skip-livecheck")
              test_bot_args << "--skip-livecheck"
              runner_audit_exceptions -= LIVECHECK_AUDITS
            end
            test_bot_args << "--except=#{runner_audit_exceptions.join(",")}" if runner_audit_exceptions.any?

            runner_output = {
              name:          "test #{cask_token} (#{runner.fetch(:name)}, #{runner.fetch(:arch)})",
              tap:           tap.name,
              testing_casks: testing_cask,
              added_casks:   added ? testing_cask : "",
              test_bot_args:,
              cask:          {
                token: cask_token,
                path:  "./#{path}",
              },
              audit_args:    runner_audit_args,
              fetch_args:    [],
              skip_install:,
              runner:        runner.fetch(:name),
            }
            if runner.fetch(:symbol) == :linux
              runner_output[:container] = {
                image:   "ghcr.io/homebrew/brew:main",
                options: "--user=linuxbrew",
              }
            end

            runner_output
          end
        end
        check_size!(jobs.size)
        jobs
      end

      sig { params(cask: Cask).returns(T::Hash[Runner, Float]) }
      def self.filter_runners(cask)
        filtered_runners = T.let({}, T::Hash[Runner, Float])
        if cask.supports_macos?
          # Skip macOS if no runner satisfies the cask's min/max macOS requirements.
          macos_requirements = [cask.depends_on.macos, cask.depends_on.maximum_macos]
                               .compact
                               .select(&:version_specified?)

          filtered_runners = if macos_requirements.empty?
            MACOS_RUNNERS.dup
          else
            MACOS_RUNNERS.select do |runner, _|
              macos_version = MacOSVersion.from_symbol(runner.fetch(:symbol).to_sym)
              macos_requirements.all? { |requirement| requirement.allows?(macos_version) }
            end
          end

          if filtered_runners.any?
            macos_archs = architectures(cask:, os: :macos)
            filtered_runners.select! do |runner, _|
              macos_archs.include?(runner.fetch(:arch))
            end
          end
        end

        if cask.supports_linux?
          linux_archs = architectures(cask:, os: :linux)
          filtered_runners.merge!(LINUX_RUNNERS.select do |runner, _|
            linux_archs.include?(runner.fetch(:arch))
          end)
        end

        # A cask that is disabled doesn't need to be tested
        filtered_runners.reject do |runner, _|
          tag = ::Utils::Bottles::Tag.new(system: runner.fetch(:symbol).to_sym, arch: runner.fetch(:arch).to_sym)
          cask.refresh_for_tag(tag) { cask.disabled? }
        end
      end

      sig { params(cask: Cask).returns(T::Array[Runner]) }
      def self.runners(cask:)
        filtered_runners = filter_runners(cask)

        filtered_macos_found = filtered_runners.keys.any? do |runner|
          cask.to_hash_with_variations["variations"].key?(runner.fetch(:symbol).to_sym)
        end

        # If the cask varies on a macOS version, test it on every possible macOS version.
        return filtered_runners.keys if filtered_macos_found

        macos_runners, linux_runners = filtered_runners.partition do |runner, _|
          runner.fetch(:symbol) != :linux
        end
        selected_runners = macos_runners.any? ? [random_runner(macos_runners.to_h)] : []
        selected_runners + linux_runners.map(&:first)
      end

      sig { params(cask: Cask, os: Symbol).returns(T::Array[Symbol]) }
      def self.architectures(cask:, os:)
        architectures = T.let([], T::Array[Symbol])
        [:arm, :intel].each do |arch|
          tag = ::Utils::Bottles::Tag.new(system: os, arch:)
          cask.refresh_for_tag(tag) do
            if cask.depends_on.arch.blank?
              architectures = RUNNERS.keys.map { |r| r.fetch(:arch).to_sym }.uniq.sort
              next
            end

            architectures = cask.depends_on.arch.map { |arch| arch[:type] }
          end
        end

        architectures
      end

      private_class_method :architectures

      sig { params(available_runners: T::Hash[Runner, Float]).returns(Runner) }
      def self.random_runner(available_runners = MACOS_RUNNERS)
        max_runner = available_runners.max_by { |(_, weight)| rand ** (1.0 / weight) }
        raise "unexpected nil max_runner" unless max_runner

        max_runner.first
      end
    end
  end
end
