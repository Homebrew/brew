# typed: strict
# frozen_string_literal: true

require "cmd/completions"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::CompletionsCmd do
  it_behaves_like "parseable arguments"

  it "uses state as the default subcommand" do
    expect(described_class.new([]).args.subcommand).to eq("state")
  end

  it "rejects extra arguments for state" do
    expect { described_class.new(%w[state foo]) }
      .to raise_error(Homebrew::CLI::MaxNamedArgumentsError)
  end

  it "links completions", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    expect { brew "completions", "link" }
      .to output(/Completions are now linked/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    Homebrew::Settings.clear_cache
    expect(Homebrew::Completions.link_completions?).to be(true)
  end
end
