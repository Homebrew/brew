# typed: strict
# frozen_string_literal: true

require "cmd/services"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Services, :needs_daemon_manager do
  it_behaves_like "parseable arguments"

  it "sets canonical subcommand names", :aggregate_failures do
    expect(described_class.new([]).args.subcommand).to eq("list")
    expect(described_class.new(%w[i testball]).args.subcommand).to eq("info")
  end

  it "rejects file-only options for info" do
    expect { described_class.new(%w[info testball --file=/tmp/service.plist]) }
      .to raise_error(UsageError, /`info` subcommand does not accept the `--file` flag/)
  end

  it "uses operation-specific --all descriptions", :aggregate_failures do
    subcommand_options = lambda do |subcommand|
      described_class.parser
                     .processed_options_for_subcommand(subcommand)
                     .filter_map do |_, long, description, hidden|
        [long, description] unless hidden
      end.to_h
    end

    expect(subcommand_options.call("start")["--all"])
      .to eq("Start all services and register them to launch at login (or boot).")
    expect(subcommand_options.call("stop")["--all"])
      .to eq("Stop all services and unregister them from launching at login (or boot), unless `--keep` is specified.")
    expect(subcommand_options.call("run")["--all"])
      .to eq("Run all services without registering them to launch at login (or boot).")
    expect(subcommand_options.call("restart")["--all"]).to eq("Restart all services.")
    expect(subcommand_options.call("kill")["--all"])
      .to eq("Stop all services immediately but keep them registered to launch at login (or boot).")
    expect(subcommand_options.call("info")["--all"]).to eq("List all managed services.")
  end

  it "allows controlling services", :integration_test do
    expect { brew "services", "list" }
      .to not_to_output.to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end
end
