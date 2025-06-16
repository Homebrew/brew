# frozen_string_literal: true

require "cmd/commands"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::CommandsCmd do
  it_behaves_like "parseable arguments"

  it "prints a list of all available commands", :integration_test do
    expect { brew "commands" }
      .to output(/Built-in commands/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
