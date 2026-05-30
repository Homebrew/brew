# typed: strict
# frozen_string_literal: true

require "tap"
require "trust"

RSpec.describe Homebrew::Trust do
  it "lets HOMEBREW_NO_REQUIRE_TAP_TRUST override HOMEBREW_REQUIRE_TAP_TRUST" do
    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect(Homebrew::Trust).not_to be_enabled
    end
  end

  it "trusts third-party taps" do
    tap = Tap.fetch("thirdparty", "foo")

    expect(Homebrew::Trust.trusted_tap?(tap)).to be(false)

    Homebrew::Trust.trust!(:tap, "thirdparty/foo")

    expect(Homebrew::Trust.trusted_tap?(tap)).to be(true)
  ensure
    Homebrew::Trust.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "ignores a trust file with a non-object JSON root" do
    trust_file = HOMEBREW_PREFIX/"var/homebrew/trust.json"
    trust_file.dirname.mkpath
    trust_file.write("[]")

    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    trust_file&.unlink if trust_file&.exist?
  end

  it "untrusts third-party taps" do
    Homebrew::Trust.trust!(:tap, "thirdparty/foo")

    expect(Homebrew::Trust.untrust!(:tap, "thirdparty/foo")).to be(true)
    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    Homebrew::Trust.clear!(:tap)
  end

  it "trusts third-party taps by default with an env hint" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { Homebrew::Trust.require_trusted_formula!("default-trust", formula_path) }
      .to output(%r{Tap thirdparty/foo was trusted by default}).to_stderr

    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(true)
  ensure
    Homebrew::Trust.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not store default trust when checking files" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    expect { expect(Homebrew::Trust.trusted_formula_file?(formula_path)).to be(true) }
      .not_to output.to_stderr

    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    Homebrew::Trust.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not trust untrusted files when trust checks are enabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
      expect(Homebrew::Trust.trusted_formula_file?(formula_path)).to be(false)
    end
  ensure
    Homebrew::Trust.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "does not store default trust when trust checks are disabled" do
    tap = Tap.fetch("thirdparty", "foo")
    formula_path = tap.formula_dir/"default-trust.rb"
    formula_path.dirname.mkpath

    with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") do
      expect { Homebrew::Trust.require_trusted_formula!("default-trust", formula_path) }
        .not_to output.to_stderr
    end

    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    Homebrew::Trust.clear!(:tap)
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end
end
