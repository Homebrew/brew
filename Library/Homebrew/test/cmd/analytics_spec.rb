# typed: strict
# frozen_string_literal: true

require "cmd/analytics"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Analytics do
  it_behaves_like "parseable arguments"

  it "uses state as the default subcommand" do
    expect(described_class.new([]).args.subcommand).to eq("state")
  end

  it "rejects extra arguments for state" do
    expect { described_class.new(%w[state foo]) }
      .to raise_error(Homebrew::CLI::MaxNamedArgumentsError)
  end

  it "disables analytics when HOMEBREW_NO_ANALYTICS is unset", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    expect { brew "analytics", "off", "HOMEBREW_NO_ANALYTICS" => nil }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    Homebrew::Settings.clear_cache
    expect(Homebrew::Settings.read(:analyticsdisabled)).to eq("true")
  end
end
