# typed: strict
# frozen_string_literal: true

require "test_runner_formula"
require "github_runner"

class GitHubRunnerMatrix
  # When bumping newest runner, run e.g. `git log -p --reverse -G "sha256 tahoe"`
  # on homebrew/core and tag the first commit with a bottle e.g.
  # `git tag 15-sequoia f42c4a659e4da887fc714f8f41cc26794a4bb320`
  # to allow people to jump to specific commits based on their macOS version.
  NEWEST_HOMEBREW_CORE_MACOS_RUNNER = :tahoe
  OLDEST_HOMEBREW_CORE_MACOS_RUNNER = :sonoma
  NEWEST_HOMEBREW_CORE_INTEL_MACOS_RUNNER = :sonoma

  RunnerSpec = T.type_alias { T.any(LinuxRunnerSpec, MacOSRunnerSpec) }
  private_constant :RunnerSpec

  MacOSRunnerSpecHash = T.type_alias do
    {
      name:             String,
      runner:           String,
      timeout:          Integer,
      cleanup:          T::Boolean,
      testing_formulae: String,
    }
  end
  private_constant :MacOSRunnerSpecHash

  LinuxRunnerSpecHash = T.type_alias do
    {
      name:             String,
      runner:           String,
      container:        T::Hash[Symbol, String],
      workdir:          String,
      timeout:          Integer,
      cleanup:          T::Boolean,
      testing_formulae: String,
    }
  end
  private_constant :LinuxRunnerSpecHash

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
      options = %w[--user linuxbrew]
      options << "--privileged" if Homebrew::EnvConfig.sandbox_linux?
      container = {
        image:   "ghcr.io/homebrew/brew:main",
        options: options.join(" "),
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
    macos_version.between?(OLDEST_HOMEBREW_CORE_MACOS_RUNNER, NEWEST_HOMEBREW_CORE_MACOS_RUNNER)
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

  NEWEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER = :ventura
  OLDEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER = :ventura
  NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER = :tahoe
  OLDEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER = :sonoma
  GITHUB_ACTIONS_RUNNER_TIMEOUT = 360
  private_constant :NEWEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER, :OLDEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER,
                   :NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER, :OLDEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER,
                   :GITHUB_ACTIONS_RUNNER_TIMEOUT

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
        name:    "macOS 10.15-cross x86_64",
        runner:  "10.15-cross-#{@github_run_id}",
        timeout: GITHUB_ACTIONS_LONG_TIMEOUT,
        cleanup: true,
      )
      x86_64_macos_version = MacOSVersion.new("10.15")
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
        ["macos-#{version}", GITHUB_ACTIONS_RUNNER_TIMEOUT]
      elsif macos_version >= :monterey
        ["#{version}-arm64#{ephemeral_suffix}", @runner_timeout]
      else
        ["#{version}-arm64", @runner_timeout]
      end

      # We test recursive dependents on ARM macOS, so they can be slower than our Intel runners.
      timeout *= 2 if @dependent_matrix && timeout < GITHUB_ACTIONS_RUNNER_TIMEOUT
      spec = MacOSRunnerSpec.new(
        name:    "macOS #{version}-arm64",
        runner:,
        timeout:,
        cleanup: !runner.end_with?(ephemeral_suffix),
      )
      @runners << create_runner(:macos, :arm64, spec, macos_version)

      skip_intel_runner = !@all_supported && macos_version > NEWEST_HOMEBREW_CORE_INTEL_MACOS_RUNNER
      skip_intel_runner &&= @dependent_matrix || @testing_formulae.none? do |testing_formula|
        bottle_spec = testing_formula.formula.bottle_specification
        bottle_spec.tag?(Utils::Bottles.tag(macos_version.to_sym), no_older_versions: true) &&
          !bottle_spec.tag?(Utils::Bottles.tag(:all), no_older_versions: true)
      end
      next if skip_intel_runner

      github_runner_available = macos_version.between?(OLDEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER,
                                                       NEWEST_GITHUB_ACTIONS_INTEL_MACOS_RUNNER)

      runner, timeout = if use_github_runner && github_runner_available
        ["macos-#{version}", GITHUB_ACTIONS_RUNNER_TIMEOUT]
      else
        ["#{version}-x86_64#{ephemeral_suffix}", @runner_timeout]
      end

      # macOS 12-x86_64 is usually slower.
      timeout += 30 if macos_version <= :monterey
      # The ARM runners are typically over twice as fast as the Intel runners.
      timeout *= 2 if !(use_github_runner && github_runner_available) && timeout < GITHUB_ACTIONS_LONG_TIMEOUT
      spec = MacOSRunnerSpec.new(
        name:    "macOS #{version}-x86_64",
        runner:,
        timeout:,
        cleanup: !runner.end_with?(ephemeral_suffix),
      )
      @runners << create_runner(:macos, :x86_64, spec, macos_version)
    end

    @runners.freeze
  end

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
      platform = runner.platform
      arch = runner.arch
      macos_version = runner.macos_version

      @testing_formulae.select do |formula|
        Homebrew::SimulateSystem.with(os: platform, arch: Homebrew::SimulateSystem.arch_symbols.fetch(arch)) do
          simulated_formula = TestRunnerFormula.new(Formulary.factory(formula.name))
          next false if macos_version && !simulated_formula.compatible_with?(macos_version)

          simulated_formula.public_send(:"#{platform}_compatible?") &&
            simulated_formula.public_send(:"#{arch}_compatible?")
        end
      end
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
            next false if macos_version && !simulated_dependent_f.compatible_with?(macos_version)

            simulated_dependent_f.public_send(:"#{platform}_compatible?") &&
              simulated_dependent_f.public_send(:"#{arch}_compatible?") &&
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
