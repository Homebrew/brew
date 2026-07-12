# typed: true
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::EnvConfig do
  subject(:env_config) { described_class }

  describe "ENVS" do
    it "sorts alphabetically" do
      expect(Homebrew::EnvConfig::ENVS.keys).to eql(Homebrew::EnvConfig::ENVS.keys.sort)
    end
  end

  describe ".env_method_name" do
    it "generates method names" do
      expect(env_config.env_method_name("HOMEBREW_FOO", {})).to eql("foo")
    end

    it "generates boolean method names" do
      expect(env_config.env_method_name("HOMEBREW_BAR", boolean: true)).to eql("bar?")
    end
  end

  describe ".env_value" do
    it "deprecates variables using ENVS metadata" do
      ENV["HOMEBREW_TEST_DEPRECATED"] = "1"

      expect { env_config.env_value(:HOMEBREW_TEST_DEPRECATED, odeprecated: true) }
        .to raise_error(MethodDeprecatedError, /HOMEBREW_TEST_DEPRECATED.*deprecated/)
    ensure
      ENV["HOMEBREW_TEST_DEPRECATED"] = nil
    end

    it "disables variables using ENVS metadata" do
      ENV["HOMEBREW_TEST_DISABLED"] = "1"

      expect { env_config.env_value(:HOMEBREW_TEST_DISABLED, odisabled: true) }
        .to raise_error(MethodDeprecatedError, /HOMEBREW_TEST_DISABLED.*disabled/)
    ensure
      ENV["HOMEBREW_TEST_DISABLED"] = nil
    end

    it "applies variable deprecations to matching commands" do
      with_env(HOMEBREW_TEST_DEPRECATED: "1", HOMEBREW_COMMAND: "install") do
        expect { env_config.env_value(:HOMEBREW_TEST_DEPRECATED, odeprecated: true, commands: ["install"]) }
          .to raise_error(MethodDeprecatedError, /HOMEBREW_TEST_DEPRECATED.*deprecated/)
      end
    end

    it "skips variable deprecations for other commands" do
      with_env(HOMEBREW_TEST_DEPRECATED: "1", HOMEBREW_COMMAND: "info") do
        expect(env_config.env_value(:HOMEBREW_TEST_DEPRECATED, odeprecated: true, commands: ["install"]))
          .to eq("1")
      end
    end

    it "applies variable deprecations to matching subcommands" do
      with_env(HOMEBREW_TEST_DEPRECATED: "1", HOMEBREW_SUBCOMMAND: "install") do
        expect { env_config.env_value(:HOMEBREW_TEST_DEPRECATED, odeprecated: true, subcommands: ["install"]) }
          .to raise_error(MethodDeprecatedError, /HOMEBREW_TEST_DEPRECATED.*deprecated/)
      end
    end

    it "skips variable deprecations for other subcommands" do
      with_env(HOMEBREW_TEST_DEPRECATED: "1", HOMEBREW_SUBCOMMAND: "dump") do
        expect(env_config.env_value(:HOMEBREW_TEST_DEPRECATED, odeprecated: true, subcommands: ["install"]))
          .to eq("1")
      end
    end
  end

  describe ".artifact_domain" do
    it "returns value if set" do
      ENV["HOMEBREW_ARTIFACT_DOMAIN"] = "https://brew.sh"
      expect(env_config.artifact_domain).to eql("https://brew.sh")
    end

    it "returns nil if empty" do
      ENV["HOMEBREW_ARTIFACT_DOMAIN"] = ""
      expect(env_config.artifact_domain).to be_nil
    end
  end

  describe ".cleanup_periodic_full_days" do
    it "returns value if set" do
      ENV["HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS"] = "360"
      expect(env_config.cleanup_periodic_full_days).to eql("360")
    end

    it "returns default if unset" do
      ENV["HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS"] = nil
      expect(env_config.cleanup_periodic_full_days).to eql("30")
    end
  end

  describe ".bat?" do
    it "returns true if set" do
      ENV["HOMEBREW_BAT"] = "1"
      expect(env_config.bat?).to be(true)
    end

    it "returns false if unset" do
      ENV["HOMEBREW_BAT"] = nil
      expect(env_config.bat?).to be(false)
    end

    it "returns false if set to a falsey value" do
      ENV["HOMEBREW_BAT"] = "0"
      expect(env_config.bat?).to be(false)
    end
  end

  describe ".ask?" do
    before do
      ENV["HOMEBREW_ASK"] = nil
      ENV["HOMEBREW_NO_ASK"] = nil
    end

    it "returns true by default" do
      expect(env_config.ask?).to be(true)
    end

    it "returns false if HOMEBREW_NO_ASK is set" do
      ENV["HOMEBREW_NO_ASK"] = "1"
      expect(env_config.ask?).to be(false)
    end

    it "deprecates HOMEBREW_ASK" do
      ENV["HOMEBREW_ASK"] = "1"
      expect { env_config.ask? }.to raise_error(MethodDeprecatedError, /HOMEBREW_ASK.*deprecated/)
    end
  end

  describe ".color?" do
    before do
      ENV["HOMEBREW_COLOR"] = nil
      ENV["HOMEBREW_NO_COLOR"] = nil
    end

    it "returns false if HOMEBREW_NO_COLOR is set" do
      ENV["HOMEBREW_COLOR"] = "1"
      ENV["HOMEBREW_NO_COLOR"] = "1"
      expect(env_config.color?).to be(false)
    end
  end

  describe ".make_jobs" do
    it "returns value if positive" do
      ENV["HOMEBREW_MAKE_JOBS"] = "4"
      expect(env_config.make_jobs).to eql("4")
    end

    it "returns default if negative" do
      ENV["HOMEBREW_MAKE_JOBS"] = "-1"
      expect(Hardware::CPU).to receive(:cores).and_return(16)
      expect(env_config.make_jobs).to eql("16")
    end
  end

  describe ".bundle_describe?" do
    it "returns true if unset" do
      with_env(HOMEBREW_BUNDLE_DESCRIBE: nil, HOMEBREW_BUNDLE_NO_DESCRIBE: nil) do
        expect(env_config.bundle_describe?).to be(true)
      end
    end

    it "returns false if HOMEBREW_BUNDLE_NO_DESCRIBE is set" do
      with_env(HOMEBREW_BUNDLE_DESCRIBE: "1", HOMEBREW_BUNDLE_NO_DESCRIBE: "1") do
        expect(env_config.bundle_describe?).to be(false)
      end
    end

    it "deprecates HOMEBREW_BUNDLE_DESCRIBE" do
      with_env(HOMEBREW_BUNDLE_DESCRIBE: "1") do
        expect { env_config.bundle_describe? }
          .to raise_error(MethodDeprecatedError, /HOMEBREW_BUNDLE_DESCRIBE.*deprecated/)
      end
    end
  end

  describe ".bundle_jobs" do
    it "returns auto if unset" do
      with_env(HOMEBREW_BUNDLE_JOBS: nil, HOMEBREW_BUNDLE_NO_JOBS: nil) do
        expect(env_config.bundle_jobs).to eql("auto")
      end
    end

    it "returns nil if HOMEBREW_BUNDLE_NO_JOBS is set" do
      with_env(HOMEBREW_BUNDLE_JOBS: "auto", HOMEBREW_BUNDLE_NO_JOBS: "1") do
        expect(env_config.bundle_jobs).to be_nil
      end
    end

    it "warns if HOMEBREW_BUNDLE_JOBS is explicitly set to the default" do
      with_env(HOMEBREW_BUNDLE_JOBS: "auto", HOMEBREW_BUNDLE_NO_JOBS: nil) do
        expect { env_config.bundle_jobs }.to output(/HOMEBREW_BUNDLE_JOBS=auto is now the default/).to_stderr
      end
    end
  end

  describe ".bundle_no_secrets?" do
    it "returns true if unset" do
      with_env(HOMEBREW_BUNDLE_NO_SECRETS: nil, HOMEBREW_BUNDLE_SECRETS: nil) do
        expect(env_config.bundle_no_secrets?).to be(true)
      end
    end

    it "returns false if HOMEBREW_BUNDLE_SECRETS is set" do
      with_env(HOMEBREW_BUNDLE_NO_SECRETS: "1", HOMEBREW_BUNDLE_SECRETS: "1") do
        expect(env_config.bundle_no_secrets?).to be(false)
      end
    end

    it "deprecates HOMEBREW_BUNDLE_NO_SECRETS" do
      with_env(HOMEBREW_BUNDLE_NO_SECRETS: "1", HOMEBREW_BUNDLE_SECRETS: nil) do
        expect { env_config.bundle_no_secrets? }
          .to raise_error(MethodDeprecatedError, /HOMEBREW_BUNDLE_NO_SECRETS.*deprecated/)
      end
    end
  end

  describe ".use_internal_api?" do
    it "deprecates HOMEBREW_USE_INTERNAL_API" do
      with_env(HOMEBREW_USE_INTERNAL_API: "1") do
        expect { env_config.use_internal_api? }
          .to raise_error(MethodDeprecatedError, /HOMEBREW_USE_INTERNAL_API.*deprecated/)
      end
    end
  end

  describe ".forbid_packages_from_paths?" do
    around do |example|
      with_env(HOMEBREW_TESTS: ENV.fetch("HOMEBREW_TESTS", nil)) { example.run }
    end

    before do
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = nil
      ENV["HOMEBREW_DEVELOPER"] = nil
      ENV["HOMEBREW_TESTS"] = nil
    end

    it "returns true if HOMEBREW_FORBID_PACKAGES_FROM_PATHS is set" do
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
      expect(env_config.forbid_packages_from_paths?).to be(true)
    end

    it "returns true if HOMEBREW_DEVELOPER is not set" do
      ENV["HOMEBREW_DEVELOPER"] = nil
      expect(env_config.forbid_packages_from_paths?).to be(true)
    end

    it "returns false if HOMEBREW_DEVELOPER is set and HOMEBREW_FORBID_PACKAGES_FROM_PATHS is not set" do
      ENV["HOMEBREW_DEVELOPER"] = "1"
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = nil
      expect(env_config.forbid_packages_from_paths?).to be(false)
    end

    it "returns true if both HOMEBREW_DEVELOPER and HOMEBREW_FORBID_PACKAGES_FROM_PATHS are set" do
      ENV["HOMEBREW_DEVELOPER"] = "1"
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
      expect(env_config.forbid_packages_from_paths?).to be(true)
    end
  end

  describe ".upgrade_auto_updates_casks?" do
    around do |example|
      with_env(
        HOMEBREW_DEVELOPER:                     nil,
        HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS:    nil,
        HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS: nil,
      ) { example.run }
    end

    it "returns true by default" do
      ENV["HOMEBREW_DEVELOPER"] = "1"
      expect(env_config.upgrade_auto_updates_casks?).to be(true)
    end

    it "returns true if set to a falsey value" do
      ENV["HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS"] = "0"
      expect(env_config.upgrade_auto_updates_casks?).to be(true)
    end

    it "returns false if HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS is set" do
      ENV["HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS"] = "1"
      ENV["HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS"] = "1"
      expect(env_config.upgrade_auto_updates_casks?).to be(false)
    end
  end

  describe ".sandbox_linux?" do
    around do |example|
      with_env(
        HOMEBREW_DEVELOPER:        nil,
        HOMEBREW_NO_SANDBOX_LINUX: nil,
        HOMEBREW_SANDBOX_LINUX:    nil,
      ) { example.run }
    end

    it "returns true by default" do
      expect(env_config.sandbox_linux?).to be(true)
    end

    it "returns true for developers" do
      ENV["HOMEBREW_DEVELOPER"] = "1"
      expect(env_config.sandbox_linux?).to be(true)
    end

    it "deprecates HOMEBREW_SANDBOX_LINUX" do
      ENV["HOMEBREW_SANDBOX_LINUX"] = "1"
      expect { env_config.sandbox_linux? }.to raise_error(MethodDeprecatedError, /HOMEBREW_SANDBOX_LINUX.*deprecated/)
    end
  end

  describe ".sbom?" do
    around do |example|
      with_env(HOMEBREW_SBOM: nil) { example.run }
    end

    it "returns true by default" do
      expect(env_config.sbom?).to be(true)
    end

    it "returns true if set to a falsey value" do
      ENV["HOMEBREW_SBOM"] = "0"
      expect(env_config.sbom?).to be(true)
    end

    it "is hidden" do
      expect(env_config.hidden?(Homebrew::EnvConfig::ENVS.fetch(:HOMEBREW_SBOM))).to be(true)
    end
  end

  describe ".no_sandbox_cask?" do
    it "deprecates HOMEBREW_NO_SANDBOX_CASK" do
      ENV["HOMEBREW_NO_SANDBOX_CASK"] = "1"
      expect { env_config.no_sandbox_cask? }
        .to raise_error(MethodDeprecatedError, /HOMEBREW_NO_SANDBOX_CASK.*deprecated/)
    ensure
      ENV["HOMEBREW_NO_SANDBOX_CASK"] = nil
    end
  end

  describe ".require_tap_trust?" do
    around do |example|
      with_env(
        HOMEBREW_REQUIRE_TAP_TRUST:    nil,
        HOMEBREW_NO_REQUIRE_TAP_TRUST: nil,
      ) { example.run }
    end

    it "returns true by default" do
      expect(env_config.require_tap_trust?).to be(true)
    end
  end

  describe ".verify_attestations?" do
    around do |example|
      with_env(
        HOMEBREW_VERIFY_ATTESTATIONS:    nil,
        HOMEBREW_NO_VERIFY_ATTESTATIONS: nil,
      ) { example.run }
    end

    it "returns false if HOMEBREW_NO_VERIFY_ATTESTATIONS is set" do
      ENV["HOMEBREW_VERIFY_ATTESTATIONS"] = "1"
      ENV["HOMEBREW_NO_VERIFY_ATTESTATIONS"] = "1"
      expect(env_config.verify_attestations?).to be(false)
    end
  end

  describe ".eval_all?" do
    before do
      ENV["HOMEBREW_EVAL_ALL"] = nil
      ENV["HOMEBREW_REQUIRE_TAP_TRUST"] = nil
      ENV["HOMEBREW_NO_REQUIRE_TAP_TRUST"] = nil
      ENV["HOMEBREW_DEVELOPER"] = nil
    end

    it "returns false if HOMEBREW_REQUIRE_TAP_TRUST is set" do
      ENV["HOMEBREW_REQUIRE_TAP_TRUST"] = "1"

      expect(env_config.eval_all?).to be(false)
    end
  end

  describe ".no_eval_env_scrubbing?" do
    it "deprecates HOMEBREW_NO_EVAL_ENV_SCRUBBING" do
      ENV["HOMEBREW_NO_EVAL_ENV_SCRUBBING"] = "1"
      expect { env_config.no_eval_env_scrubbing? }
        .to raise_error(MethodDeprecatedError, /HOMEBREW_NO_EVAL_ENV_SCRUBBING.*deprecated/)
    ensure
      ENV["HOMEBREW_NO_EVAL_ENV_SCRUBBING"] = nil
    end
  end

  describe ".tap_trust_configured?" do
    before do
      ENV["HOMEBREW_REQUIRE_TAP_TRUST"] = nil
      ENV["HOMEBREW_NO_REQUIRE_TAP_TRUST"] = nil
    end

    it "returns true by default" do
      expect(env_config.tap_trust_configured?).to be(true)
      expect(env_config.require_tap_trust?).to be(true)
    end

    it "returns true if HOMEBREW_REQUIRE_TAP_TRUST is set" do
      ENV["HOMEBREW_REQUIRE_TAP_TRUST"] = "1"

      expect(env_config.tap_trust_configured?).to be(true)
      expect(env_config.require_tap_trust?).to be(true)
    end
  end
end
