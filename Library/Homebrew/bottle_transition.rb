# typed: strict
# frozen_string_literal: true

require "formula"
require "formulary"
require "test_runner_formula"

# Preserve bottles while bootstrapping a macOS release.
# TODO: remove this class and its callers when `HOMEBREW_MACOS_NEWEST_SUPPORTED` is `27`.
class BottleTransition
  MACOS = :golden_gate

  sig { returns(Utils::Bottles::Tag) }
  def self.tag
    Utils::Bottles::Tag.new(system: MACOS, arch: :arm64)
  end

  sig { returns(T::Boolean) }
  def self.active?
    MacOSVersion.from_symbol(MACOS) > HOMEBREW_MACOS_NEWEST_SUPPORTED
  end

  sig { params(base_ref: T.nilable(String)).void }
  def initialize(base_ref: nil)
    if self.class.active? && ENV.fetch("GITHUB_EVENT_NAME", nil) == "merge_group"
      event = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH")))
      base_ref = event.dig("merge_group", "base_sha")
      if !base_ref.is_a?(String) || !/\A[0-9a-f]{40}\z/.match?(base_ref)
        raise UsageError, "Missing immutable merge-group base SHA."
      end
    end
    base_branch = ENV.fetch("GITHUB_BASE_REF", nil).presence
    @base_ref = T.let(base_ref || (base_branch ? "origin/#{base_branch}" : "origin/HEAD"), String)
    @base_revision = T.let(nil, T.nilable(String))
    @required = T.let({}, T::Hash[String, T::Boolean])
  end

  sig { params(formula: Formula).returns(T::Boolean) }
  def required?(formula)
    return false unless self.class.active?
    return false unless formula.tap&.core_tap?
    return false if formula.disabled?

    compatible = Homebrew::SimulateSystem.with(os: MACOS, arch: :arm) do
      candidate = TestRunnerFormula.new(Formulary.factory(formula.path))
      candidate.compatible?(platform: :macos, arch: :arm64, macos_version: MacOSVersion.from_symbol(MACOS))
    end
    return false unless compatible

    @required.fetch(formula.name) do
      repository = CoreTap.instance.path
      @base_revision ||= Utils.safe_popen_read("git", "-C", repository, "rev-parse", "--verify",
                                               "#{@base_ref}^{commit}").strip
      path = formula.tap_path.relative_path_from(repository)
      files = Utils.safe_popen_read("git", "-C", repository, "ls-tree", "--name-only", "-z",
                                    @base_revision, "--", path)
      return @required[formula.name] = false if files.empty?

      contents = Utils.safe_popen_read("git", "-C", repository, "show", "#{@base_revision}:#{path}")
      @required[formula.name] = Homebrew::SimulateSystem.with(os: MACOS, arch: :arm) do
        previous = Formulary.from_contents(formula.name, formula.tap_path, contents)
        previous.bottle_specification.collector.tags.include?(self.class.tag)
      end
    end
  end

  sig { params(formula: Formula, tags: T::Array[Utils::Bottles::Tag]).void }
  def check!(formula, tags:)
    return unless required?(formula)
    return if tags.include?(self.class.tag) || tags.include?(Utils::Bottles.tag(:all))

    raise UsageError, <<~EOS
      #{formula.full_name} already has #{self.class.tag} bottle coverage on #{@base_ref}.
      Build an #{self.class.tag} bottle for #{formula.pkg_version} before publishing or merging.
      Re-run CI against the updated base branch if mass bottling finished after CI started.
    EOS
  end
end
