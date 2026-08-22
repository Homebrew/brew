# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/formula-analytics"
require "json"
require "uri"
require "utils/analytics"

RSpec.describe Homebrew::DevCmd::FormulaAnalytics do
  it_behaves_like "parseable arguments"

  describe "#format_os_version_dimension" do
    it "preserves WSL in formatted Linux versions" do
      expect(described_class.new([]).format_os_version_dimension(
               "Ubuntu 24.04.3 LTS#{Utils::Analytics::WSL_SUFFIX}",
             )).to eq("Ubuntu 24.04 LTS#{Utils::Analytics::WSL_SUFFIX}")
    end
  end

  describe "#influx_analytics" do
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
      command = described_class.new(["--homebrew-env-config", "--json"])
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

      expect { command.influx_analytics(command.args) }
        .to output("#{JSON.pretty_generate(expected)}\n").to_stdout
      expect(queries).to contain_exactly(
        match(/FROM "command_run".*env_config_state IS NOT NULL GROUP BY/).and(
          include('GROUP BY "env_config","env_config_state"'),
        ),
      )
    end
  end

  describe "#each_influx_record" do
    it "streams the JSON request to the bridge script and parses JSON lines" do
      command = described_class.new([])
      bridge = mktmpdir/"fake-python"
      bridge.write "#!/bin/sh\ncat\n"
      bridge.chmod 0755
      allow(command).to receive(:venv_python).and_return(bridge)
      records = []

      command.each_influx_record("SELECT 1") { |record| records << record }

      expect(records).to eq [{
        "host"     => URI.parse(Utils::Analytics::INFLUX_HOST).host,
        "org"      => Utils::Analytics::INFLUX_ORG,
        "database" => Utils::Analytics::INFLUX_BUCKET,
        "query"    => "SELECT 1",
      }]
    end

    it "reports unauthenticated bridge errors as a token problem" do
      command = described_class.new([])
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
      command = described_class.new([])
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
