# frozen_string_literal: true

require "utils/analytics"
require "formula_installer"

RSpec.describe Utils::Analytics do
  describe "::default_package_tags" do
    let(:ci) { ", CI" if ENV["CI"] }

    it "returns OS_VERSION and prefix when HOMEBREW_PREFIX is a custom prefix on intel" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:prefix)
      expect(described_class.default_package_tags[:prefix]).to eq "custom-prefix"
    end

    it "returns OS_VERSION, ARM and prefix when HOMEBREW_PREFIX is a custom prefix on arm" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:arch)
      expect(described_class.default_package_tags[:arch]).to eq HOMEBREW_PHYSICAL_PROCESSOR
      expect(described_class.default_package_tags).to have_key(:prefix)
      expect(described_class.default_package_tags[:prefix]).to eq "custom-prefix"
    end

    it "returns OS_VERSION, Rosetta and prefix when HOMEBREW_PREFIX is a custom prefix on Rosetta", :needs_macos do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:prefix)
      expect(described_class.default_package_tags[:prefix]).to eq "custom-prefix"
    end

    it "does not include prefix when HOMEBREW_PREFIX is the default prefix" do
      expect(Homebrew).to receive(:default_prefix?).and_return(true).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:prefix)
      expect(described_class.default_package_tags[:prefix]).to eq HOMEBREW_PREFIX.to_s
    end

    it "includes CI when ENV['CI'] is set" do
      ENV["CI"] = "1"
      expect(described_class.default_package_tags).to have_key(:ci)
    end

    it "includes developer when ENV['HOMEBREW_DEVELOPER'] is set" do
      expect(Homebrew::EnvConfig).to receive(:developer?).and_return(true)
      expect(described_class.default_package_tags).to have_key(:developer)
    end
  end

  describe "::report_package_event" do
    let(:f) { formula { url "foo-1.0" } }
    let(:package_name)  { f.name }
    let(:tap_name) { f.tap.name }
    let(:on_request) { false }
    let(:options) { "--HEAD" }

    context "when ENV vars is set" do
      it "returns nil when HOMEBREW_NO_ANALYTICS is true" do
        ENV["HOMEBREW_NO_ANALYTICS"] = "true"
        expect(described_class).not_to receive(:report_influx)
        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end

      it "returns nil when HOMEBREW_NO_ANALYTICS_THIS_RUN is true" do
        ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "true"
        expect(described_class).not_to receive(:report_influx)
        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end

      it "returns nil when HOMEBREW_ANALYTICS_DEBUG is true" do
        ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
        ENV.delete("HOMEBREW_NO_ANALYTICS")
        ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
        expect(described_class).to receive(:report_influx)

        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end
    end

    it "passes to the influxdb method" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:report_influx).with(:install, hash_including(on_request:),
                                                              hash_including(package: package_name)).once
      described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
    end
  end

  describe "::report_influx" do
    let(:f) { formula { url "foo-1.0" } }
    let(:package)  { f.name }
    let(:tap_name) { f.tap.name }
    let(:on_request) { false }
    let(:options) { "--HEAD" }

    it "outputs in debug mode" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:deferred_curl).once
      described_class.report_influx(:install, { on_request: }, { package:, tap_name: })
    end
  end

  describe "::report_build_error" do
    context "when tap is installed" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { formula { url "foo-1.0" } }

      it "reports event if BuildError raised for a formula with a public remote repository" do
        allow_any_instance_of(Tap).to receive(:custom_remote?).and_return(false)
        expect(described_class).to respond_to(:report_package_event)
        described_class.report_build_error(err)
      end

      it "does not report event if BuildError raised for a formula with a private remote repository" do
        allow_any_instance_of(Tap).to receive(:private?).and_return(true)
        expect(described_class).not_to receive(:report_package_event)
        described_class.report_build_error(err)
      end
    end

    context "when formula does not have a tap" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { instance_double(Formula, name: "foo", path: "blah", tap: nil) }

      it "does not report event if BuildError is raised" do
        expect(described_class).not_to receive(:report_package_event)
        described_class.report_build_error(err)
      end
    end

    context "when tap for a formula is not installed" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { instance_double(Formula, name: "foo", path: "blah", tap: CoreTap.instance) }

      it "does not report event if BuildError is raised" do
        allow_any_instance_of(Pathname).to receive(:directory?).and_return(false)
        expect(described_class).not_to receive(:report_package_event)
        described_class.report_build_error(err)
      end
    end
  end

  describe "::report_command_run" do
    let(:command) { "audit" }
    let(:options) { "--tap=" }
    let(:command_instance) do
      require "dev-cmd/audit"
      Homebrew::DevCmd::Audit.new(["--tap=homebrew/core"])
    end

    it "passes to the influxdb method" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:report_influx).with(
        :command_run,
        hash_including(command:),
        hash_including(options:),
      ).once
      described_class.report_command_run(command_instance)
    end
  end

  describe "::report_test_bot_test" do
    let(:command) { "install wget" }
    let(:passed) { true }

    it "passes to the influxdb method" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      ENV["HOMEBREW_TEST_BOT_ANALYTICS"] = "true"
      expect(described_class).to receive(:report_influx).with(
        :test_bot_test,
        hash_including(passed:),
        hash_including(command:),
      ).once
      described_class.report_test_bot_test(command, passed)
    end
  end

  specify "::table_output" do
    results = { ack: 10, wget: 100 }
    expect { described_class.table_output("install", "30", results) }
      .to output(/110 |  100.00%/).to_stdout
      .and not_to_output.to_stderr
  end
end
