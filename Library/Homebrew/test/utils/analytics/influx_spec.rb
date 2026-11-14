# typed: strict
# frozen_string_literal: true

require "utils/analytics/influx"
require "json"
require "utils/analytics"

RSpec.describe Utils::Analytics::Influx do
  describe "#format_os_version_dimension" do
    it "formats retired macOS versions" do
      expect(described_class.new.format_os_version_dimension("10.15.7"))
        .to eq("macOS Catalina (10.15)")
    end

    it "normalizes Big Sur compatibility versions" do
      expect(described_class.new.format_os_version_dimension("10.16.0"))
        .to eq("macOS Big Sur (11)")
    end

    it "formats retired OS X versions" do
      expect(described_class.new.format_os_version_dimension("10.11.6"))
        .to eq("OS X El Capitan (10.11)")
    end

    it "formats unknown legacy macOS versions" do
      expect(described_class.new.format_os_version_dimension("10.10.5")).to eq("OS X 10.10")
    end

    it "formats unknown future macOS versions" do
      expect(described_class.new.format_os_version_dimension("28.0")).to eq("macOS 28")
    end

    it "does not format malformed macOS versions" do
      expect(described_class.new.format_os_version_dimension("10.15.invalid")).to eq("10.15.invalid")
    end

    it "formats Debian point releases as major releases" do
      expect(described_class.new.format_os_version_dimension("Debian GNU/Linux 12.11")).to eq("Debian 12")
    end

    it "formats Debian major releases" do
      expect(described_class.new.format_os_version_dimension("Debian GNU/Linux 12")).to eq("Debian 12")
    end

    it "preserves WSL in formatted Linux versions" do
      expect(described_class.new.format_os_version_dimension(
               "Ubuntu 24.04.3 LTS#{Utils::Analytics::WSL_SUFFIX}",
             )).to eq("Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}")
    end
  end

  describe "#query" do
    it "queries package analytics without preloaded tap classes" do
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
      ENV["HOMEBREW_INFLUXDB_TOKEN"] = "token"
      stdout, stderr, status = Open3.capture3(
        *HOMEBREW_RUBY_EXEC_ARGS, "-I", HOMEBREW_LIBRARY_PATH, "-rglobal", "-e", <<~RUBY
          require "api"
          require "utils/analytics/influx"

          module Homebrew::API
            def self.formula_renames = { "old-name" => "new-name" }
            def self.cask_renames = { "old-name" => "new-name" }
            def self.formula_tap_migrations = {}
            def self.cask_tap_migrations = {}
          end

          influx = Utils::Analytics::Influx.new
          def influx.each_influx_record(query)
            tap = query.include?('FROM "cask_install"') ? "homebrew/cask" : "homebrew/core"
            yield({ "package" => "old-name", "tap_name" => tap, "count" => 2 })
            yield({ "package" => "new-name", "tap_name" => tap, "count" => 3 })
          end

          puts JSON.generate(influx.query(categories: [:formula_install, :cask_install]).map { |report| report[:items] })
        RUBY
      )
      raise stderr unless status.success?

      expect(JSON.parse(stdout)).to eq([
        [{ "number" => 1, "formula" => "new-name", "count" => "5", "percent" => "100" }],
        [{ "number" => 1, "cask" => "new-name", "count" => "5", "percent" => "100" }],
      ])
    end

    context "with package renames and tap migrations" do
      before do
        ENV.delete("HOMEBREW_NO_ANALYTICS")
        ENV["HOMEBREW_INFLUXDB_TOKEN"] = "token"
        allow(Tap).to receive(:all).and_return(
          [CoreTap.instance, CoreCaskTap.instance, Tap.fetch("homebrew/old"), Tap.fetch("user/tap")],
        )
        allow(CoreTap.instance).to receive_messages(
          formula_renames: { "old-formula" => "new-formula" },
          cask_renames:    {},
          tap_migrations:  { "moved-formula" => "user/tap/new-formula" },
        )
        allow(CoreCaskTap.instance).to receive_messages(
          formula_renames: {},
          cask_renames:    { "old-cask" => "new-cask" },
          tap_migrations:  { "moved-cask" => "user/tap/new-cask" },
        )
        allow(Tap.fetch("homebrew/old")).to receive_messages(
          formula_renames: {},
          cask_renames:    {},
          tap_migrations:  { "old-formula" => "homebrew/core/old-formula",
                             "old-cask"    => "homebrew/cask" },
        )
        [:formula_renames, :cask_renames, :tap_migrations].each do |method|
          allow(Tap.fetch("user/tap")).to receive(method).and_raise("Unexpected third-party metadata read")
        end
      end

      [[:formula_install, :formula, "homebrew/core"],
       [:formula_install_on_request, :formula, "homebrew/core"],
       [:build_error, :formula, "homebrew/core"],
       [:cask_install, :cask, "homebrew/cask"]].each do |category, dimension, tap_name|
        it "combines renamed #{category} rows and updates totals" do
          T.bind(self, RSpec::Core::ExampleGroup)
          command = described_class.new
          allow(command).to receive(:each_influx_record)
            .and_yield({ "package" => "old-#{dimension}", "tap_name" => tap_name, "count" => 2 })
            .and_yield({ "package" => "new-#{dimension}", "tap_name" => tap_name, "count" => 3 })

          expect(command.query(categories: [category]).fetch(0)).to include(
            total_items: 1,
            total_count: 5,
            items:       [{ number: 1, dimension => "new-#{dimension}", count: "5", percent: "100" }],
          )
        end

        it "combines migrated #{category} rows under their destination tap" do
          T.bind(self, RSpec::Core::ExampleGroup)
          command = described_class.new
          allow(command).to receive(:each_influx_record)
            .and_yield({ "package" => "moved-#{dimension}", "tap_name" => tap_name, "count" => 2 })
            .and_yield({ "package" => "new-#{dimension}", "tap_name" => "user/tap", "count" => 3 })

          expect(command.query(categories: [category]).fetch(0)).to include(
            total_items: 1,
            total_count: 5,
            items:       [{ number: 1, dimension => "user/tap/new-#{dimension}", count: "5", percent: "100" }],
          )
        end

        it "resolves migrations before filtering #{category} to official packages" do
          T.bind(self, RSpec::Core::ExampleGroup)
          command = described_class.new
          allow(command).to receive(:each_influx_record) do |query, &block|
            records = [
              { "package" => "old-#{dimension}", "tap_name" => "homebrew/old", "count" => 2 },
              { "package" => "new-#{dimension}", "tap_name" => tap_name, "count" => 3 },
              { "package" => "moved-#{dimension}", "tap_name" => tap_name, "count" => 7 },
              { "package" => "new-#{dimension}", "tap_name" => "unrelated/tap", "count" => 11 },
            ]
            if query.include?("^homebrew/(core|cask)$")
              records.select! { |record| record["tap_name"] == tap_name }
            end
            records.each(&block)
          end

          expect(command.query(categories: [category], all_core_formulae_json: true).fetch(0)).to include(
            total_items: 1,
            total_count: 5,
            formulae:    { "new-#{dimension}" => [{ dimension => "new-#{dimension}", count: "5" }] },
          )
        end

        it "keeps third-party #{category} names separate without reading their metadata" do
          T.bind(self, RSpec::Core::ExampleGroup)
          command = described_class.new
          allow(command).to receive(:each_influx_record)
            .and_yield({ "package" => "old-#{dimension}", "tap_name" => tap_name, "count" => 5 })
            .and_yield({ "package" => "old-#{dimension}", "tap_name" => "user/tap", "count" => 5 })
            .and_yield({ "package" => "new-#{dimension}", "tap_name" => "user/tap", "count" => 5 })

          expect(command.query(categories: [category]).fetch(0).fetch(:items)).to eq([
            { number: 1, dimension => "new-#{dimension}", count: "5", percent: "33.33" },
            { number: 2, dimension => "user/tap/old-#{dimension}", count: "5", percent: "33.33" },
            { number: 3, dimension => "user/tap/new-#{dimension}", count: "5", percent: "33.33" },
          ])
        end
      end

      it "keeps HEAD counts separate after resolving formula renames" do
        command = described_class.new
        allow(command).to receive(:each_influx_record)
          .and_yield({ "package" => "old-formula", "tap_name" => "homebrew/core", "count" => 2,
                       "options" => "--HEAD --unrelated" })
          .and_yield({ "package" => "new-formula", "tap_name" => "homebrew/core", "count" => 3,
                       "options" => "--HEAD" })
          .and_yield({ "package" => "new-formula", "tap_name" => "homebrew/core", "count" => 7 })

        expect(command.query(categories: [:formula_install], all_core_formulae_json: true).fetch(0)).to include(
          total_items: 2,
          total_count: 12,
          formulae:    { "new-formula" => [{ formula: "new-formula", count: "7" },
                                           { formula: "new-formula --HEAD", count: "5" }] },
        )
      end

      it "does not loop on cyclic renames" do
        command = described_class.new
        allow(CoreTap.instance).to receive(:formula_renames).and_return("old-formula" => "old-formula")
        allow(command).to receive(:each_influx_record)
          .and_yield({ "package" => "old-formula", "tap_name" => "homebrew/core", "count" => 2 })

        expect(command.query(categories: [:formula_install]).fetch(0).fetch(:items))
          .to eq([{ number: 1, formula: "old-formula", count: "2", percent: "100" }])
      end
    end

    it "ranks sampled environment configurations by non-default use" do
      ENV.delete("HOMEBREW_NO_ANALYTICS")
      ENV["HOMEBREW_INFLUXDB_TOKEN"] = "token"
      records = [
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "non_default", "count" => 2 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "default", "count" => 3 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "unset", "count" => 5 },
        { "env_config" => "HOMEBREW_NO_AUTO_UPDATE", "env_config_state" => "non_default", "count" => 1 },
        { "env_config" => "HOMEBREW_NO_AUTO_UPDATE", "env_config_state" => "unset", "count" => 1 },
        { "env_config" => "HOMEBREW_MAKE_JOBS", "env_config_state" => "default", "count" => 4 },
        { "env_config" => "HOMEBREW_TOTALLY_MADE_UP", "env_config_state" => "non_default", "count" => 100 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "borked", "count" => 50 },
      ]
      queries = []
      command = described_class.new
      allow(command).to receive(:each_influx_record) do |query, &block|
        queries << query
        records.each(&block)
      end
      expected = {
        category:    :homebrew_env_config,
        total_items: 3,
        start_date:  Date.today - 30,
        end_date:    Date.today,
        total_count: 16,
        items:       [
          {
            number: 1, env_config: "HOMEBREW_NO_AUTO_UPDATE", count: "2", non_default_count: "1",
            set_default_count: "0", unset_count: "1", percent: "50", default_value: nil
          },
          {
            number: 2, env_config: "HOMEBREW_BAT", count: "10", non_default_count: "2",
            set_default_count: "3", unset_count: "5", percent: "20", default_value: nil
          },
          {
            number: 3, env_config: "HOMEBREW_MAKE_JOBS", count: "4", non_default_count: "0",
            set_default_count: "4", unset_count: "0", percent: "0",
            default_value: "The number of available CPU cores."
          },
        ],
      }

      expect(JSON.pretty_generate(command.query(categories: [:homebrew_env_config]).fetch(0)))
        .to eq(JSON.pretty_generate(expected))
      expect(queries).to contain_exactly(
        match(/FROM "command_run".*env_config_state IS NOT NULL GROUP BY/).and(
          include('GROUP BY "env_config","env_config_state"'),
        ),
      )
    end
  end

  describe "#each_influx_record" do
    it "streams the JSON request to the bridge script and parses JSON lines" do
      command = described_class.new
      bridge = mktmpdir/"fake-python"
      bridge.write "#!/bin/sh\ncat\n"
      bridge.chmod 0755
      allow(command).to receive(:venv_python).and_return(bridge)
      records = []

      command.each_influx_record("SELECT 1") { |record| records << record }

      expect(records).to eq [{
        "host"     => "eu-central-1-1.aws.cloud2.influxdata.com",
        "org"      => Utils::Analytics::INFLUX_ORG,
        "database" => Utils::Analytics::INFLUX_BUCKET,
        "query"    => "SELECT 1",
      }]
    end

    it "reports unauthenticated bridge errors as a token problem" do
      command = described_class.new
      bridge = mktmpdir/"fake-python"
      bridge.write <<~SH
        #!/bin/sh
        cat >/dev/null
        echo "pyarrow.flight.FlightUnauthenticatedError: message: unauthenticated" >&2
        exit 1
      SH
      bridge.chmod 0755
      allow(command).to receive(:venv_python).and_return(bridge)

      expect { command.each_influx_record("SELECT 1") { nil } }
        .to raise_error(SystemExit)
        .and output(/Could not authenticate with InfluxDB/).to_stderr
    end

    it "reports other bridge failures with their standard error output" do
      command = described_class.new
      bridge = mktmpdir/"fake-python"
      bridge.write <<~SH
        #!/bin/sh
        cat >/dev/null
        echo "Traceback: boom" >&2
        exit 1
      SH
      bridge.chmod 0755
      allow(command).to receive(:venv_python).and_return(bridge)

      expect { command.each_influx_record("SELECT 1") { nil } }
        .to raise_error(SystemExit)
        .and output(/InfluxDB query failed:\nTraceback: boom/).to_stderr
    end
  end
end
