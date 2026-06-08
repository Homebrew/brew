# typed: strict
# frozen_string_literal: true

require "tap"
require "trust"
require "tmpdir"

RSpec.describe Homebrew::Trust do
  around do |example|
    Dir.mktmpdir do |config_home|
      with_env(HOMEBREW_USER_CONFIG_HOME: config_home) { example.run }
    end
  end

  it "lets HOMEBREW_NO_REQUIRE_TAP_TRUST override HOMEBREW_REQUIRE_TAP_TRUST" do
    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect(Homebrew::EnvConfig.require_tap_trust?).to be(false)
    end
  end

  it "trusts third-party taps" do
    tap = Tap.fetch("thirdparty", "foo")

    expect(described_class.trusted_tap?(tap)).to be(false)

    described_class.trust!(:tap, "thirdparty/foo")

    expect(described_class.trusted_tap?(tap)).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "trusts formulae from trusted taps" do
    Tap.fetch("trustedformulae", "foo")

    described_class.trust!(:tap, "trustedformulae/foo")

    expect(described_class.trusted?(:formula, "trustedformulae/foo/bar")).to be(true)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"trustedformulae"
  end

  it "ignores a trust file with a non-object JSON root" do
    trust_file = T.let(nil, T.nilable(Pathname))
    trust_file = described_class.trust_file
    trust_file.dirname.mkpath
    trust_file.write("[]")

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    trust_file.unlink if trust_file&.exist?
  end

  it "untrusts third-party taps" do
    described_class.trust!(:tap, "thirdparty/foo")

    expect(described_class.untrust!(:tap, "thirdparty/foo")).to be(true)
    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
  end

  it "trusts fully-qualified formulae and casks" do
    tap = Tap.fetch("qualified", "foo")
    tap.formula_dir.mkpath
    tap.cask_dir.mkpath
    (tap.formula_dir/"bar.rb").write("class Bar < Formula; end\n")
    (tap.cask_dir/"baz.rb").write("cask 'baz'\n")

    described_class.trust_fully_qualified_items!(["qualified/foo/bar", "qualified/foo/baz"])

    expect(described_class.trusted?(:formula, "qualified/foo/bar")).to be(true)
    expect(described_class.trusted?(:cask, "qualified/foo/baz")).to be(true)
  ensure
    described_class.clear!(:formula)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"qualified"
  end

  it "does not trust missing fully-qualified formulae or casks" do
    Tap.fetch("thirdparty", "foo")

    described_class.trust_fully_qualified_items!(["thirdparty/foo/bar"], type: :formula)
    described_class.trust_fully_qualified_items!(["thirdparty/foo/baz"], type: :cask)

    expect(described_class.trusted?(:formula, "thirdparty/foo/bar")).to be(false)
    expect(described_class.trusted?(:cask, "thirdparty/foo/baz")).to be(false)
  ensure
    described_class.clear!(:formula)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not report taps with trusted entries as wholly untrusted" do
    allow(described_class).to receive(:untrusted_taps)
      .and_return([instance_double(Tap, name: "thirdparty/foo")])
    described_class.trust!(:formula, "thirdparty/foo/bar")

    expect(described_class.wholly_untrusted_taps).to be_empty
  ensure
    described_class.clear!(:formula)
  end

  it "writes the trust store with user-only permissions" do
    described_class.trust!(:tap, "thirdparty/foo")

    trust_file = described_class.trust_file
    expect(trust_file.stat.mode & 0777).to eq(0600)
  ensure
    described_class.clear!(:tap)
  end

  it "requires third-party taps by default" do
    described_class.clear!(:tap)
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { described_class.require_trusted_formula!("default-trust", formula_path) }
      .to raise_error(Homebrew::UntrustedTapError)

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust or store default trust when checking files" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { expect(described_class.trusted_formula_file?(formula_path)).to be(false) }
      .not_to output.to_stderr

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust untrusted files when trust checks are enabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect(described_class.trusted_formula_file?(formula_path)).to be(false)
    end
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "allows explicitly named formula files when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["thirdparty/foo/default-trust"])
      expect(described_class.trusted_formula_file?(formula_path)).to be(true)
    end

    expect(described_class.trusted?(:formula, "thirdparty/foo/default-trust")).to be(false)
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:tap)
    described_class.clear!(:formula)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "allows files from explicitly named taps when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    cask_path = tap.cask_dir/"default-trust.rb"
    cask_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["--tap", "thirdparty/foo"])
      expect(described_class.trusted_cask_file?(cask_path)).to be(true)
    end

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
    expect(described_class.trusted?(:cask, "thirdparty/foo/default-trust")).to be(false)
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:tap)
    described_class.clear!(:cask)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not allow explicitly named command files when trust checks are enabled" do
    old_argv = ARGV.dup
    tap = Tap.fetch("thirdparty", "foo")
    command_path = tap.path/"cmd/brew-default-trust.rb"
    command_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      ARGV.replace(["thirdparty/foo/default-trust"])
      expect(described_class.trusted_command_files([command_path])).to eq([])
    end
  ensure
    ARGV.replace(old_argv) if old_argv
    described_class.clear!(:command)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust untrusted command files when trust checks are enabled" do
    tap = Tap.fetch("thirdparty", "foo")
    command_path = tap.path/"cmd/brew-default-trust.rb"
    command_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect { expect(described_class.trusted_command_files([command_path])).to eq([]) }
        .to output(%r{Skipping thirdparty/foo because it is not trusted}).to_stderr
    end
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not store default trust when trust checks are disabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect { described_class.require_trusted_formula!("default-trust", formula_path) }
        .not_to output.to_stderr
    end

    expect(described_class.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    described_class.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end
end
