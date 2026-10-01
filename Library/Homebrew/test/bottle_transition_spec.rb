# typed: strict
# frozen_string_literal: true

require "bottle_transition"

RSpec.describe BottleTransition do
  sig { returns(BottleTransition) }
  subject(:transition) { described_class.new }

  sig { returns(String) }
  def current_contents
    <<~RUBY
      class TransitionTest < Formula
        url "https://brew.sh/transition-test-2.0.tar.gz"
      end
    RUBY
  end
  sig { returns(Formula) }
  let(:current) do
    path = CoreTap.instance.path/"Formula/t/transition-test.rb"
    path.dirname.mkpath
    path.write(current_contents)
    Homebrew::SimulateSystem.with(os: :linux, arch: :intel) { Formulary.factory(path) }
  end

  sig { returns(String) }
  def base_revision
    "a" * 40
  end

  sig { returns(String) }
  def base_contents
    <<~RUBY
      class TransitionTest < Formula
        url "https://brew.sh/transition-test-1.0.tar.gz"
        bottle do
          sha256 arm64_golden_gate: "#{"b" * 64}"
        end
      end
    RUBY
  end

  before do
    stub_const("HOMEBREW_MACOS_NEWEST_SUPPORTED", "26")
    ENV.delete("GITHUB_BASE_REF")
    ENV.delete("GITHUB_EVENT_NAME")
    allow(Utils).to receive(:safe_popen_read).and_call_original
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", CoreTap.instance.path, "rev-parse", "--verify", "origin/HEAD^{commit}")
      .and_return("#{base_revision}\n")
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", CoreTap.instance.path, "ls-tree", "--name-only", "-z", base_revision,
            "--", current.tap_path.relative_path_from(CoreTap.instance.path))
      .and_return("#{current.tap_path.relative_path_from(CoreTap.instance.path)}\0")
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", CoreTap.instance.path, "show",
            "#{base_revision}:#{current.tap_path.relative_path_from(CoreTap.instance.path)}")
      .and_return(base_contents)
  end

  it "uses base-branch coverage even when the new version has no bottle block" do
    expect(transition.required?(current)).to be true
  end

  it "does not enrol a formula with only older macOS bottles" do
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", CoreTap.instance.path, "show",
            "#{base_revision}:#{current.tap_path.relative_path_from(CoreTap.instance.path)}")
      .and_return(base_contents.sub("arm64_golden_gate", "arm64_tahoe"))

    expect(transition.required?(current)).to be false
  end

  it "rejects publication that drops transition coverage" do
    expect do
      transition.check!(current, tags: [Utils::Bottles.tag(:arm64_tahoe)])
    end.to raise_error(UsageError, /Build an arm64_golden_gate bottle for 2.0/)
  end

  it "accepts an all bottle as replacement coverage" do
    expect { transition.check!(current, tags: [Utils::Bottles.tag(:all)]) }.not_to raise_error
  end

  context "when the base has a universal bottle" do
    it "does not enrol universal bottles in transition CI" do
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "show",
              "#{base_revision}:#{current.tap_path.relative_path_from(CoreTap.instance.path)}")
        .and_return(base_contents.sub("arm64_golden_gate", "all"))

      expect(transition.required?(current)).to be false
    end
  end

  context "when a formula no longer supports macOS" do
    sig { returns(String) }
    def current_contents
      super.sub("class TransitionTest < Formula", "class TransitionTest < Formula\n  depends_on :linux")
    end

    it "allows its macOS coverage to be retired" do
      expect(transition.required?(current)).to be false
    end
  end

  context "when a requirement exists only on macOS" do
    sig { returns(String) }
    def current_contents
      super.sub("class TransitionTest < Formula", <<~RUBY)
        class TransitionTest < Formula
          on_macos do
            depends_on maximum_macos: :tahoe
          end
      RUBY
    end

    it "checks Golden Gate compatibility even when called on Linux" do
      expect(transition.required?(current)).to be false
    end
  end

  context "when a pull request targets a topic branch" do
    it "checks coverage against that branch" do
      ENV["GITHUB_BASE_REF"] = "topic"
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "rev-parse", "--verify", "origin/topic^{commit}")
        .and_return("#{base_revision}\n")
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "rev-parse", "--verify", "origin/HEAD^{commit}")
        .and_raise("Wrong base branch")

      expect(transition.required?(current)).to be true
    end
  end

  context "when the package version is unchanged" do
    it "still requires evidence of transition coverage" do
      allow(current).to receive(:pkg_version).and_return(PkgVersion.parse("1.0"))

      expect do
        transition.check!(current, tags: [Utils::Bottles.tag(:arm64_tahoe)])
      end.to raise_error(UsageError, /before publishing or merging/)
    end
  end

  context "when the formula is new" do
    it "does not require transition coverage" do
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "ls-tree", "--name-only", "-z", base_revision,
              "--", current.tap_path.relative_path_from(CoreTap.instance.path))
        .and_return("")

      expect(transition.required?(current)).to be false
    end
  end

  context "when the transition OS is fully supported" do
    before { stub_const("HOMEBREW_MACOS_NEWEST_SUPPORTED", "27") }

    it "ends the transition policy" do
      expect(transition.required?(current)).to be false
    end

    it "does not require a merge-group event payload" do
      ENV["GITHUB_EVENT_NAME"] = "merge_group"
      ENV.delete("GITHUB_EVENT_PATH")

      expect { transition.check!(current, tags: []) }.not_to raise_error
    end
  end

  context "when running against a pull request base branch" do
    it "uses the base branch instead of the default branch" do
      ENV["GITHUB_BASE_REF"] = "example"
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "rev-parse", "--verify", "origin/example^{commit}")
        .and_return("#{base_revision}\n")

      expect(transition.required?(current)).to be true
    end
  end

  context "when running in the merge queue" do
    it "uses the immutable merge-group base" do
      event_path = mktmpdir/"event.json"
      event_path.write(JSON.generate({ merge_group: { base_sha: base_revision } }))
      ENV["GITHUB_EVENT_NAME"] = "merge_group"
      ENV["GITHUB_EVENT_PATH"] = event_path.to_s
      allow(Utils).to receive(:safe_popen_read)
        .with("git", "-C", CoreTap.instance.path, "rev-parse", "--verify", "#{base_revision}^{commit}")
        .and_return("#{base_revision}\n")

      expect(transition.required?(current)).to be true
    end

    it "rejects a mutable or malformed merge-group base" do
      event_path = mktmpdir/"event.json"
      event_path.write(JSON.generate({ merge_group: { base_sha: "main" } }))
      ENV["GITHUB_EVENT_NAME"] = "merge_group"
      ENV["GITHUB_EVENT_PATH"] = event_path.to_s

      expect { transition }.to raise_error(UsageError, /immutable merge-group base SHA/)
    end
  end

  it "fails closed when the base formula cannot be loaded" do
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", CoreTap.instance.path, "show",
            "#{base_revision}:#{current.tap_path.relative_path_from(CoreTap.instance.path)}")
      .and_return("class TransitionTest < Formula\ninvalid ruby\n")

    expect { transition.required?(current) }.to raise_error(FormulaUnreadableError)
  end
end
