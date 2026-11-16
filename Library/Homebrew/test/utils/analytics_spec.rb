# typed: true
# frozen_string_literal: true

require "utils/analytics"
require "formula_installer"
require "cmd/info"

RSpec.describe Utils::Analytics do
  describe "::with_wsl_suffix_if_needed" do
    it "adds WSL by default on WSL" do
      allow(OS).to receive(:wsl?).and_return(true)

      expect(described_class.with_wsl_suffix_if_needed("Ubuntu 24.04 LTS")).to eq(
        "Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}",
      )
    end

    it "does not add WSL with an explicit override" do
      expect(described_class.with_wsl_suffix_if_needed("Ubuntu 24.04 LTS", wsl: false)).to eq("Ubuntu 24.04 LTS")
    end

    it "does not add duplicate WSL suffixes" do
      expect(described_class.with_wsl_suffix_if_needed("Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}", wsl: true))
        .to eq("Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}")
    end
  end

  describe "::default_package_tags" do
    let(:ci) { ", CI" if ENV["CI"] }

    it "returns a custom prefix tag when HOMEBREW_PREFIX is a custom prefix" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:prefix)
      expect(described_class.default_package_tags[:prefix]).to eq "custom-prefix"
    end

    it "returns the physical processor when HOMEBREW_PREFIX is a custom prefix" do
      expect(Homebrew).to receive(:default_prefix?).and_return(false).at_least(:once)
      expect(described_class.default_package_tags).to have_key(:arch)
      expect(described_class.default_package_tags[:arch]).to eq HOMEBREW_PHYSICAL_PROCESSOR
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

    it "includes WSL in the OS tag on WSL" do
      described_class.clear_cache
      allow(OS).to receive(:wsl?).and_return(true)

      expect(described_class.default_package_tags[:os]).to eq("#{HOMEBREW_SYSTEM}#{Utils::Analytics::WSL_SUFFIX}")
    end
  end

  describe "::default_package_fields" do
    it "includes WSL in the OS name and version on WSL" do
      described_class.clear_cache
      allow(OS).to receive(:wsl?).and_return(true)

      expect(described_class.default_package_fields[:os_name_and_version]).to eq("#{OS_VERSION}#{Utils::Analytics::WSL_SUFFIX}")
    end
  end

  describe "::report_package_event" do
    let(:f) do
      formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
    end
    let(:package_name) { f.name }
    let(:tap_name) { f.tap.name }
    let(:on_request) { false }
    let(:options) { "--HEAD" }

    context "when ENV vars is set" do
      it "returns nil when HOMEBREW_NO_ANALYTICS is true" do
        ENV["HOMEBREW_NO_ANALYTICS"] = "true"
        expect(described_class).not_to receive(:write_influx)
        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end

      it "returns nil when HOMEBREW_NO_ANALYTICS_THIS_RUN is true" do
        ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "true"
        expect(described_class).not_to receive(:write_influx)
        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end

      it "returns nil when HOMEBREW_ANALYTICS_DEBUG is true" do
        ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
        ENV.delete("HOMEBREW_NO_ANALYTICS")
        ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
        expect(described_class).to receive(:write_influx)

        described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
      end
    end

    it "passes to the influxdb method" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      expect(described_class).to receive(:write_influx).with(
        [a_string_including("install,", "on_request=#{on_request}", "package=\"#{package_name}\"")],
      ).once
      described_class.report_package_event(:install, package_name:, tap_name:,
          on_request:, options:)
    end
  end

  describe "::report_package_events" do
    it "reports all the packages in a single request" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      allow(Time).to receive(:now).and_return(Time.at(123))
      allow(described_class).to receive_messages(default_package_tags:   { ci: false },
                                                 default_package_fields: { version: "1.0" })
      expect(described_class).to receive(:deferred_curl).once.with(
        anything,
        array_including(
          "--data-binary",
          "formula_install,ci=false,on_request=true version=\"1.0\",package=\"foo\"," \
          "tap_name=\"homebrew/core\" 123\n" \
          "formula_install,ci=false,on_request=false version=\"1.0\",package=\"bar\"," \
          "tap_name=\"homebrew/core\",options=\"--HEAD\" 123",
        ),
      )

      described_class.report_package_events(:formula_install, [
        { package_name: "foo", tap_name: "homebrew/core", on_request: true, options: "" },
        { package_name: "bar", tap_name: "homebrew/core", on_request: false, options: "--HEAD" },
      ])
    end

    it "does not report when analytics are disabled" do
      ENV["HOMEBREW_NO_ANALYTICS"] = "1"
      expect(described_class).not_to receive(:write_influx)

      described_class.report_package_events(:formula_install, [
        { package_name: "foo", tap_name: "homebrew/core", on_request: true, options: "" },
      ])
    end
  end

  describe "::report_formula_installs" do
    it "reports each formula and dependency to install once" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      shared_dep = { package_name: "shared", tap_name: "homebrew/core", on_request: false, options: "" }
      foo = { package_name: "foo", tap_name: "homebrew/core", on_request: true, options: "" }
      bar = { package_name: "bar", tap_name: "homebrew/core", on_request: true, options: "" }
      formula_installers = [
        instance_double(FormulaInstaller, install_analytics_events: [shared_dep, foo]),
        instance_double(FormulaInstaller, install_analytics_events: [shared_dep, bar]),
      ]
      expect(described_class).to receive(:report_package_events).with(:formula_install, [shared_dep, foo, bar])

      described_class.report_formula_installs(formula_installers)
    end

    it "does not look at the formulae when analytics are disabled" do
      ENV["HOMEBREW_NO_ANALYTICS"] = "1"
      formula_installer = instance_double(FormulaInstaller)
      expect(formula_installer).not_to receive(:install_analytics_events)
      expect(described_class).not_to receive(:report_package_events)

      described_class.report_formula_installs([formula_installer])
    end
  end

  describe "::report_cask_installs" do
    it "reports the casks from taps that report analytics" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      reporting_tap = instance_double(Tap, name: "homebrew/cask", should_report_analytics?: true)
      casks = [
        instance_double(Cask::Cask, token: "foo", tap: reporting_tap),
        instance_double(Cask::Cask, token: "bar", tap: instance_double(Tap, should_report_analytics?: false)),
        instance_double(Cask::Cask, token: "baz", tap: nil),
      ]
      expect(described_class).to receive(:report_package_events).with(
        :cask_install,
        [{ package_name: "foo", tap_name: "homebrew/cask", on_request: true, options: "" }],
      )

      described_class.report_cask_installs(casks)
    end
  end

  describe "::report_influx" do
    let(:f) do
      formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
    end
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

    it "escapes WSL tag values for Influx line protocol" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      allow(Time).to receive(:now).and_return(Time.at(123))
      expect(described_class).to receive(:deferred_curl).with(
        anything,
        array_including(
          "--data-binary",
          'formula_install,os=Linux\ [WSL] os_name_and_version="Ubuntu 24.04 LTS [WSL]" 123',
        ),
      )

      described_class.report_influx(
        :formula_install,
        { os: "Linux#{Utils::Analytics::WSL_SUFFIX}" },
        { os_name_and_version: "Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}" },
      )
    end
  end

  describe "::write_influx" do
    it "sends all the lines in a single request" do
      expect(described_class).to receive(:deferred_curl).once.with(
        anything,
        array_including("--data-binary", "a,t=1 f=\"1\" 123\nb,t=2 f=\"2\" 123"),
      )

      described_class.write_influx(["a,t=1 f=\"1\" 123", "b,t=2 f=\"2\" 123"])
    end

    it "splits lines larger than INFLUX_MAX_BATCH_BYTES into multiple requests" do
      # Exactly enough room for two lines and the newline between them.
      stub_const("Utils::Analytics::INFLUX_MAX_BATCH_BYTES", ("a,t=1 f=\"1\" 123".bytesize * 2) + 1)
      requests = []
      allow(described_class).to receive(:deferred_curl) { |_url, args| requests << args }

      described_class.write_influx(["a,t=1 f=\"1\" 123", "b,t=2 f=\"2\" 123", "c,t=3 f=\"3\" 123"])

      expect(requests.map { |args| args[args.index("--data-binary") + 1] }).to eq([
        "a,t=1 f=\"1\" 123\nb,t=2 f=\"2\" 123",
        "c,t=3 f=\"3\" 123",
      ])
    end

    it "sends a line larger than INFLUX_MAX_BATCH_BYTES in its own request" do
      stub_const("Utils::Analytics::INFLUX_MAX_BATCH_BYTES", 10)
      requests = []
      allow(described_class).to receive(:deferred_curl) { |_url, args| requests << args }

      described_class.write_influx(["a,t=1 f=\"1\" 123", "b,t=2 f=\"2\" 123"])

      expect(requests.map { |args| args[args.index("--data-binary") + 1] }).to eq([
        "a,t=1 f=\"1\" 123",
        "b,t=2 f=\"2\" 123",
      ])
    end

    it "does not send a request without any lines" do
      expect(described_class).not_to receive(:deferred_curl)

      described_class.write_influx([])
    end
  end

  describe "::deferred_curl" do
    it "forwards args and silences subprocess output outside debug mode" do
      ENV.delete("HOMEBREW_ANALYTICS_DEBUG")

      allow(Utils::Curl).to receive(:curl_executable).and_return("/usr/bin/curl")
      allow(Utils::Curl).to receive(:curl_args) { |*args, **| args }
      expect(described_class).to receive(:spawn)
        .with("/usr/bin/curl", "--max-time", "3", "--silent", "--output", File::NULL, "https://example.com",
              out: File::NULL, err: File::NULL)
        .and_return(123)
      expect(Process).to receive(:detach).with(123)

      described_class.deferred_curl("https://example.com", ["--max-time", "3"])
    end
  end

  describe "::report_build_error" do
    context "when tap is installed" do
      let(:err) { BuildError.new(f, "badprg", %w[arg1 arg2], {}) }
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
        end
      end

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
      expect(Homebrew::EnvConfig).not_to receive(:non_default_variable?)
      expect(described_class).to receive(:report_influx).with(
        :command_run,
        hash_including(command:),
        hash_including(options:),
      ).once
      described_class.report_command_run(command_instance)
    end

    it "samples one environment configuration for selected commands" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      allow(command_instance.class).to receive(:command_name).and_return("update")
      stub_const("Homebrew::EnvConfig::ANALYTICS_VARIABLES", [:HOMEBREW_ALLOWED_TAPS])
      ENV["HOMEBREW_ALLOWED_TAPS"] = "homebrew/core"
      ENV["HOMEBREW_USER_SET_VARS"] = "HOMEBREW_ALLOWED_TAPS"
      expect(Homebrew::EnvConfig).to receive(:non_default_variable?).with(:HOMEBREW_ALLOWED_TAPS).and_return(true)

      expect(described_class).to receive(:report_influx).with(
        :command_run,
        hash_including(
          command:          "update",
          env_config:       "HOMEBREW_ALLOWED_TAPS",
          env_config_state: "non_default",
        ),
        hash_including(options:),
      ).once
      described_class.report_command_run(command_instance)
    end

    it "samples variables exported by brew itself as unset" do
      ENV.delete("HOMEBREW_NO_ANALYTICS_THIS_RUN")
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_ANALYTICS_DEBUG"] = "true"
      allow(command_instance.class).to receive(:command_name).and_return("update")
      stub_const("Homebrew::EnvConfig::ANALYTICS_VARIABLES", [:HOMEBREW_ALLOWED_TAPS])
      ENV["HOMEBREW_ALLOWED_TAPS"] = "homebrew/core"
      ENV["HOMEBREW_USER_SET_VARS"] = ""

      expect(described_class).to receive(:report_influx).with(
        :command_run,
        hash_including(env_config: "HOMEBREW_ALLOWED_TAPS", env_config_state: "unset"),
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
    results = { "ack" => 10, "wget" => 100 }
    expect { described_class.table_output("install", "30", results) }
      .to output(/110 |  100.00%/).to_stdout
      .and not_to_output.to_stderr
  end

  describe "::output_github_packages_downloads" do
    let(:analytics) { { "install" => { "30d" => { "wget" => 750_000, "wget --HEAD" => 500 } } } }
    let(:args) { Homebrew::Cmd::Info.new(["--github-packages-downloads", "wget"]).args }
    let(:wget) { instance_double(Formula, name: "wget", core_formula?: true) }

    it "outputs package totals and their ratio to analytics install events" do
      allow(GitHubPackages).to receive(:downloads).with("wget").and_return(
        GitHubPackages::Downloads.new(source: "https://github.com/example", all_time: 22_776_486,
                                      last_30_days: 1_501_000, start_date: "2026-09-23", end_date: "2026-10-23",
                                      fetched_at: "2026-10-23T12:00:00Z"),
      )

      expect { described_class.output_github_packages_downloads(wget, analytics, args:) }
        .to output(
          include("GitHub Packages downloads (since Bintray migration): 22,776,486",
                  "GitHub Packages downloads (30 days): 1,501,000",
                  "Downloads / analytics install events (30 days): 2.00x (750,500 events)"),
        ).to_stdout
    end

    it "warns instead of reporting missing download counts as zero" do
      allow(GitHubPackages).to receive(:downloads).with("wget").and_return(nil)

      expect { described_class.output_github_packages_downloads(wget, analytics, args:) }
        .to output(/Failed to fetch GitHub Packages downloads for: wget/).to_stderr
        .and not_to_output.to_stdout
    end
  end
end
