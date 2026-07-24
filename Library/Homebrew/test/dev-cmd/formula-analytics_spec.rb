# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/formula-analytics"
require "json"
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
      batch = double(to_pylist: [
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "non_default", "count" => 2 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "default", "count" => 3 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "unset", "count" => 5 },
        { "env_config" => "HOMEBREW_NO_AUTO_UPDATE", "env_config_state" => "non_default", "count" => 1 },
        { "env_config" => "HOMEBREW_NO_AUTO_UPDATE", "env_config_state" => "unset", "count" => 1 },
        { "env_config" => "HOMEBREW_MAKE_JOBS", "env_config_state" => "default", "count" => 4 },
        { "env_config" => "HOMEBREW_TOTALLY_MADE_UP", "env_config_state" => "non_default", "count" => 100 },
        { "env_config" => "HOMEBREW_BAT", "env_config_state" => "borked", "count" => 50 },
      ])
      query_result = double(to_batches: [batch])
      queries = []
      influxdb_client = Class.new do
        define_method(:initialize) { |**| nil }
        define_method(:query) do |query:, language:|
          queries << { query:, language: }
          query_result
        end
      end
      stub_const("InfluxDBClient3", influxdb_client)
      command = described_class.new(["--homebrew-env-config", "--json"])
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
        query:    match(/FROM "command_run".*env_config_state IS NOT NULL GROUP BY/).and(
          include('GROUP BY "env_config","env_config_state"'),
        ),
        language: "sql",
      )
    end
  end
end
