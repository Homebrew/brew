# typed: strict
# frozen_string_literal: true

require "test_runner_formula"
require "github_runner"
require "bottle_transition"
require "utils/output"

class GitHubRunnerMatrix
  include Utils::Output::Mixin

  # When bumping newest runner, run e.g. `git log -p --reverse -G "sha256 tahoe"`
  # on homebrew/core and tag the first commit with a bottle e.g.
  # `git tag 15-sequoia f42c4a659e4da887fc714f8f41cc26794a4bb320`
  # to allow people to jump to specific commits based on their macOS version.
  NEWEST_HOMEBREW_CORE_MACOS_RUNNER = :golden_gate
  OLDEST_HOMEBREW_CORE_MACOS_RUNNER = :sequoia

  RunnerSpec = T.type_alias { T.any(LinuxRunnerSpec, MacOSRunnerSpec) }
  private_constant :RunnerSpec

  RunnerSpecHash = T.type_alias { T::Hash[Symbol, T.untyped] }
  private_constant :RunnerSpecHash
  sig { returns(T::Array[GitHubRunner]) }
  attr_reader :runners

  sig {
    params(
      testing_formulae: T::Array[TestRunnerFormula],
      deleted_formulae: T::Array[String],
      all_supported:    T::Boolean,
      dependent_matrix: T::Boolean,
      dependent_shards: T.nilable(Integer),
    ).void
  }
  def initialize(testing_formulae, deleted_formulae, all_supported:, dependent_matrix:, dependent_shards: nil)
    if all_supported && (testing_formulae.present? || deleted_formulae.present? || dependent_matrix)
      raise ArgumentError, "all_supported is mutually exclusive to other arguments"
    end

    @testing_formulae = testing_formulae
    @deleted_formulae = deleted_formulae
    @all_supported = all_supported
    @dependent_matrix = dependent_matrix
    @dependent_shards = T.let(dependent_shards || 1, Integer)
    @compatible_testing_formulae = T.let({}, T::Hash[GitHubRunner, T::Array[TestRunnerFormula]])
    @formulae_with_untested_dependents = T.let({}, T::Hash[GitHubRunner, T::Array[TestRunnerFormula]])

    # gracefully handle non-GitHub Actions environments
    @github_run_id = T.let(
      if ENV.key?("GITHUB_ACTIONS")
        ENV.fetch("GITHUB_RUN_ID")
      else
        ENV.fetch("GITHUB_RUN_ID", "")
      end, String
    )
    @linux_self_hosted = T.let(ENV.fetch("HOMEBREW_LINUX_SELF_HOSTED", "false") == "true", T::Boolean)
    @runner_timeout = T.let(
      if ENV.fetch("HOMEBREW_MACOS_LONG_TIMEOUT", "false") == "true"
        GITHUB_ACTIONS_LONG_TIMEOUT
      else
        GITHUB_ACTIONS_SHORT_TIMEOUT
      end, Integer
    )

    @runners = T.let([], T::Array[GitHubRunner])
    generate_runners!

    freeze
  end

  sig { returns(T::Array[RunnerSpecHash]) }
  def active_runner_specs_hash
    specs = runners.select(&:active)
                   .map(&:spec)
                   .map(&:to_h)
    return specs if !@dependent_matrix || @dependent_shards == 1

    specs.flat_map do |spec|
      (1..@dependent_shards).map do |shard|
        spec.merge(
          name:                      "#{spec.fetch(:name)} shard #{shard}/#{@dependent_shards}",
          runner:                    spec.fetch(:runner).sub("-deps", "-deps#{shard}").to_s,
          formulae_dependents_shard: "#{shard}/#{@dependent_shards}",
        )
      end
    end
  end

  sig { void }
  def generate_runners!
    return if @runners.present?

    if !@all_supported || @linux_self_hosted
      VALID_ARCHES.each do |arch|
        @runners << create_runner(:linux, arch, linux_runner_spec(arch, self_hosted: @linux_self_hosted))
      end
    end

    # Portable Ruby logic
    if @testing_formulae.any? { |tf| tf.name.start_with?("portable-") }
      x86_64_spec = MacOSRunnerSpec.new(
        name:         "macOS 11-cross x86_64",
        runner:       "macos-15-intel",
        timeout:      GITHUB_ACTIONS_RUNNER_TIMEOUT,
        cleanup:      true,
        target_macos: "11.7.10",
      )
      x86_64_macos_version = MacOSVersion.new("11")
      @runners << create_runner(:macos, :x86_64, x86_64_spec, x86_64_macos_version)

      # odisabled: remove support for Big Sur September (or later) 2027
      arm64_spec = MacOSRunnerSpec.new(
        name:    "macOS 11-cross arm64",
        runner:  "11-arm64-cross-#{@github_run_id}",
        timeout: GITHUB_ACTIONS_LONG_TIMEOUT,
        cleanup: true,
      )
      arm64_macos_version = MacOSVersion.new("11")
      @runners << create_runner(:macos, :arm64, arm64_spec, arm64_macos_version)
      return
    end

    # Use GitHub Actions macOS Runner for testing dependents if compatible with timeout.
    use_github_runner = ENV.fetch("HOMEBREW_MACOS_BUILD_ON_GITHUB_RUNNER", "false") == "true"
    use_github_runner ||= @dependent_matrix
    use_github_runner &&= @runner_timeout <= GITHUB_ACTIONS_RUNNER_TIMEOUT

    MacOSVersion::SYMBOLS.each_value do |version|
      macos_version = MacOSVersion.new(version)
      next unless runner_enabled?(macos_version)

      github_runner_available = macos_version.between?(OLDEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER,
                                                       NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER)

      runner, timeout = if use_github_runner && github_runner_available
        prefix = (macos_version >= "27") ? "xcode" : "macos"
        ["#{prefix}-#{version}", GITHUB_ACTIONS_RUNNER_TIMEOUT]
      elsif macos_version >= :monterey
        ["#{version}-arm64#{ephemeral_suffix}", @runner_timeout]
      else
        ["#{version}-arm64", @runner_timeout]
      end

      # Testing recursive dependents takes longer, so give those jobs two hours.
      timeout *= 2 if @dependent_matrix && timeout < GITHUB_ACTIONS_RUNNER_TIMEOUT
      spec = MacOSRunnerSpec.new(
        name:    "macOS #{version}-arm64",
        runner:,
        timeout:,
        cleanup: !runner.end_with?(ephemeral_suffix),
      )
      @runners << create_runner(:macos, :arm64, spec, macos_version)
    end

    @runners.freeze
  end

  private

  # ARM macOS timeout, keep this under 1/2 of GitHub's job execution time limit for self-hosted runners.
  # https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#usage-limits
  GITHUB_ACTIONS_LONG_TIMEOUT = 2160 # 36 hours
  GITHUB_ACTIONS_SHORT_TIMEOUT = 60
  private_constant :GITHUB_ACTIONS_LONG_TIMEOUT, :GITHUB_ACTIONS_SHORT_TIMEOUT

  sig { params(arch: Symbol, self_hosted: T::Boolean).returns(LinuxRunnerSpec) }
  def linux_runner_spec(arch, self_hosted:)
    linux_runner = case arch
    when :arm64 then self_hosted ? "linux-arm64#{ephemeral_suffix}" : OS::LINUX_CI_ARM_RUNNER
    when :x86_64 then self_hosted ? "linux-x86_64#{ephemeral_suffix}" : "ubuntu-latest"
    else raise "Unknown Linux architecture: #{arch}"
    end

    unless self_hosted
      container = {
        image:   "ghcr.io/homebrew/brew:main",
        options: "--init --user linuxbrew",
      }
      workdir = "/github/home"
    end

    LinuxRunnerSpec.new(
      name:      "Linux #{arch}",
      runner:    linux_runner,
      container:,
      workdir:,
      timeout:   GITHUB_ACTIONS_LONG_TIMEOUT,
      cleanup:   false,
    )
  end

  VALID_PLATFORMS = [:macos, :linux].freeze
  VALID_ARCHES = [:arm64, :x86_64].freeze
  private_constant :VALID_PLATFORMS, :VALID_ARCHES

  sig {
    params(
      platform:      Symbol,
      arch:          Symbol,
      spec:          RunnerSpec,
      macos_version: T.nilable(MacOSVersion),
    ).returns(GitHubRunner)
  }
  def create_runner(platform, arch, spec, macos_version = nil)
    raise "Unexpected platform: #{platform}" if VALID_PLATFORMS.exclude?(platform)
    raise "Unexpected arch: #{arch}" if VALID_ARCHES.exclude?(arch)

    runner = GitHubRunner.new(platform:, arch:, spec:, macos_version:)
    runner.spec.testing_formulae += testable_formulae(runner)
    runner.active = active_runner?(runner)
    runner.freeze
  end

  sig { params(macos_version: MacOSVersion).returns(T::Boolean) }
  def runner_enabled?(macos_version)
    return true if macos_version.between?(OLDEST_HOMEBREW_CORE_MACOS_RUNNER, NEWEST_HOMEBREW_CORE_MACOS_RUNNER)
    return false if @all_supported || @dependent_matrix

    macos_version.to_sym == BottleTransition::MACOS && transition_formulae.present?
  end

  sig { returns(T::Array[TestRunnerFormula]) }
  def transition_formulae
    @transition_formulae ||= T.let(begin
      transition = BottleTransition.new
      covered = @testing_formulae.select { |formula| transition.required?(formula.formula) }
      needed_names = []
      testing_names = @testing_formulae.map(&:name)

      Homebrew::SimulateSystem.with(os: BottleTransition::MACOS, arch: :arm) do
        covered.each do |formula|
          dependencies = Formulary.factory(formula.name).recursive_dependencies do |dependent, dependency|
            next Dependable::PRUNE if dependency.optional?

            if dependency.test? && !dependency.build? && testing_names.exclude?(dependency.name) &&
               transition_test_dependency_bottled?(dependency.to_formula)
              next Dependable::PRUNE
            end
            if dependency.is_a?(UsesFromMacOSDependency) && dependency.use_macos_install?
              next Dependable::PRUNE
            end
            next unless dependent.is_a?(Formula)
            next unless dependency.build?
            next if testing_names.include?(dependent.name)

            Dependable::PRUNE unless dependent.bottle_specification.tag?(Utils::Bottles.tag(:all))
          end
          missing = dependencies.reject do |dependency|
            dependency_formula = dependency.to_formula
            if testing_names.include?(dependency.name)
              candidate = TestRunnerFormula.new(dependency_formula)
              candidate.compatible?(platform: :macos, arch: :arm64,
                                    macos_version: BottleTransition.tag.to_macos_version)
            else
              dependency_formula.bottle_specification.tag?(BottleTransition.tag, no_older_versions: true)
            end
          end
          if missing.present?
            opoo <<~EOS
              Skipping #{formula.name}'s #{BottleTransition.tag} build: unavailable dependencies: #{missing.map(&:name).join(", ")}.
              Resolve these dependencies and retry CI before publishing.
            EOS
            next
          end

          needed_names << formula.name
          needed_names.concat(dependencies.map(&:name) & testing_names)
        end
      end

      @testing_formulae.select { |formula| needed_names.include?(formula.name) }
    end, T.nilable(T::Array[TestRunnerFormula]))
  end

  sig { params(formula: Formula).returns(T::Boolean) }
  def transition_test_dependency_bottled?(formula)
    spec = formula.bottle_specification
    if spec.tag?(Utils::Bottles.tag(:all))
      return formula.deps.all? { |dependency| transition_test_dependency_bottled?(dependency.to_formula) }
    end

    # Runner selection also runs on Linux, without macOS bottle fallback.
    spec.collector.tags.any? do |tag|
      tag.macos? && tag.standardized_arch == BottleTransition.tag.standardized_arch &&
        tag.to_macos_version <= BottleTransition.tag.to_macos_version
    end
  end

  sig { returns(String) }
  def ephemeral_suffix
    @ephemeral_suffix ||= T.let(begin
      suffix = "-#{@github_run_id}"
      suffix << "-deps" if @dependent_matrix
      suffix << "-long" if @runner_timeout == GITHUB_ACTIONS_LONG_TIMEOUT
      suffix.freeze
    end, T.nilable(String))
  end

  NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER = :golden_gate
  OLDEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER = :sonoma
  GITHUB_ACTIONS_RUNNER_TIMEOUT = 360
  private_constant :NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER, :OLDEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER,
                   :GITHUB_ACTIONS_RUNNER_TIMEOUT

  sig { params(runner: GitHubRunner).returns(T::Array[String]) }
  def testable_formulae(runner)
    formulae = if @dependent_matrix
      formulae_with_untested_dependents(runner)
    else
      compatible_testing_formulae(runner)
    end

    formulae.map(&:name)
  end

  sig { params(runner: GitHubRunner).returns(T::Boolean) }
  def active_runner?(runner)
    return true if @all_supported
    return true if @deleted_formulae.present? && !@dependent_matrix

    runner.spec.testing_formulae.present?
  end

  sig { params(runner: GitHubRunner).returns(T::Array[TestRunnerFormula]) }
  def compatible_testing_formulae(runner)
    @compatible_testing_formulae[runner] ||= begin
      macos_version = runner.macos_version
      tag = Utils::Bottles::Tag.new(system: macos_version&.to_sym || runner.platform, arch: runner.arch)

      transition_runner = BottleTransition.active? && macos_version&.to_sym == BottleTransition::MACOS
      testing_formulae = transition_runner ? transition_formulae : @testing_formulae

      testing_formulae.select { |formula| formula.compatible_with_tag?(tag) }
    end
  end

  sig { params(runner: GitHubRunner).returns(T::Array[TestRunnerFormula]) }
  def formulae_with_untested_dependents(runner)
    @formulae_with_untested_dependents[runner] ||= begin
      platform = runner.platform
      arch = runner.arch
      macos_version = runner.macos_version

      compatible_testing_formulae(runner).select do |formula|
        compatible_dependents = formula.dependents(platform:, arch:, macos_version: macos_version&.to_sym)
                                       .select do |dependent_f|
          Homebrew::SimulateSystem.with(os: platform, arch: Homebrew::SimulateSystem.arch_symbols.fetch(arch)) do
            simulated_dependent_f = dependent_f
            simulated_dependent_f.compatible?(platform:, arch:, macos_version:) &&
              !simulated_dependent_f.formula.disabled? &&
              !simulated_dependent_f.formula.deprecated?
          end
        end

        # These arrays will generally have been generated by different Formulary caches,
        # so we can only compare them by name and not directly.
        (compatible_dependents.map(&:name) - @testing_formulae.map(&:name)).present?
      end
    end
  end
end
