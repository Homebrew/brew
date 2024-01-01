# frozen_string_literal: true

require "utils/analytics"
require "formula_installer"

describe Utils::Analytics do
  before do
    described_class.clear_cache
  end

  describe "::default_tags_influx" do
    let(:ci) { ", CI" if ENV["CI"] }

    it "returns OS_VERSION and prefix when HOMEBREW_PREFIX is a custom prefix on intel" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_tags_influx).to have_key(:prefix)
      expect(described_class.default_tags_influx[:prefix]).to eq "custom-prefix"
    end

    it "returns OS_VERSION, ARM and prefix when HOMEBREW_PREFIX is a custom prefix on arm" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_tags_influx).to have_key(:arch)
      expect(described_class.default_tags_influx[:arch]).to eq HOMEBREW_PHYSICAL_PROCESSOR
      expect(described_class.default_tags_influx).to have_key(:prefix)
      expect(described_class.default_tags_influx[:prefix]).to eq "custom-prefix"
    end

    it "returns OS_VERSION, Rosetta and prefix when HOMEBREW_PREFIX is a custom prefix on Rosetta", :needs_macos do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_tags_influx).to have_key(:prefix)
      expect(described_class.default_tags_influx[:prefix]).to eq "custom-prefix"
    end

    it "does not include prefix when HOMEBREW_PREFIX is the default prefix" do
      expect(Homebrew).to receive(:default_prefix?).and_return(true).at_least(:once)
      expect(described_class.default_tags_influx).to have_key(:prefix)
      expect(described_class.default_tags_influx[:prefix]).to eq HOMEBREW_PREFIX.to_s
    end

    it "includes CI when ENV['CI'] is set" do
      ENV["CI"] = "1"
      expect(described_class.default_tags_influx).to have_key(:ci)
    end

    it "includes developer when ENV['HOMEBREW_DEVELOPER'] is set" do
      expect(Homebrew::EnvConfig).to receive(:developer?).and_return(true)
      expect(described_class.default_tags_influx).to have_key(:developer)
    end
  end

  describe "::report_event" do
    let(:f) { formula { url "foo-1.0" } }
    let(:package_name)  { f.name }
    let(:tap_name) { f.tap.name }
    let(:on_request) { false }
    let(:options) { "--HEAD" }

    context "when ENV vars is set" do
      it "returns nil when HOMEBREW_NO_ANALYTICS is true" do
        ENV["HOMEBREW_NO_ANALYTICS"] = "true"
        expect(described_class).not_to receive(:report_influx)
        described_class.report_event(:install, package_name: package_name, tap_name: tap_name,
          on_request: on_request, options: options)
      end

      it "returns nil when HOMEBREW_NO_ANALYTICS_THIS_RUN is true" do
        ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "true"
        expect(described_class).not_to receive(:report_influx)
        described_class.report_event(:install, package_name: package_name, tap_name: tap_name,
          on_request: on_request, options: options)
      end

      it "returns nil when HOMEBREW_ANALYTICS_DEBUG is true" do
        ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
        ENV.delete("HOMEBREW_NO_ANALYTICS")
        ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
        expect(described_class).to receive(:report_influx)

        described_class.report_event(:install, package_name: package_name, tap_name: tap_name,
          on_request: on_request, options: options)
      end
    end

    it "passes to the influxdb method" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:report_influx).with(:install, hash_including(package_name: package_name,
                                                                                       on_request:   on_request)).once
      described_class.report_event(:install, package_name: package_name, tap_name: tap_name,
          on_request: on_request, options: options)
    end
  end

  describe "::report_influx" do
    let(:f) { formula { url "foo-1.0" } }
    let(:package_name)  { f.name }
    let(:tap_name) { f.tap.name }
    let(:on_request) { false }
    let(:options) { "--HEAD" }

    it "outputs in debug mode" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:deferred_curl).once
      described_class.report_influx(:install, package_name: package_name, tap_name: tap_name, on_request: on_request,
options: options)
    end
  end

  describe "::report_build_error" do
    context "when tap is installed" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { formula { url "foo-1.0" } }

      it "reports event if BuildError raised for a formula with a public remote repository" do
        allow_any_instance_of(Tap).to receive(:custom_remote?).and_return(false)
        expect(described_class).to respond_to(:report_event)
        described_class.report_build_error(err)
      end

      it "does not report event if BuildError raised for a formula with a private remote repository" do
        allow_any_instance_of(Tap).to receive(:private?).and_return(true)
        expect(described_class).not_to receive(:report_event)
        described_class.report_build_error(err)
      end
    end

    context "when formula does not have a tap" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { instance_double(Formula, name: "foo", path: "blah", tap: nil) }

      it "does not report event if BuildError is raised" do
        expect(described_class).not_to receive(:report_event)
        described_class.report_build_error(err)
      end
    end

    context "when tap for a formula is not installed" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) { instance_double(Formula, name: "foo", path: "blah", tap: CoreTap.instance) }

      it "does not report event if BuildError is raised" do
        allow_any_instance_of(Pathname).to receive(:directory?).and_return(false)
        expect(described_class).not_to receive(:report_event)
        described_class.report_build_error(err)
      end
    end
  end

  specify "::table_output" do
    results = { ack: 10, wget: 100 }
    expect { described_class.table_output("install", "30", results) }
      .to output(/110 |  100.00%/).to_stdout
      .and not_to_output.to_stderr
  end
end
