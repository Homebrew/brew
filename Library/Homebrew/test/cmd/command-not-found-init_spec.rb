# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/command-not-found-init"

RSpec.describe Homebrew::Cmd::CommandNotFoundInit do
  it_behaves_like "parseable arguments"

  it "prints a handler script when output is not connected to a tty", :integration_test do
    expect { brew "command-not-found-init" }
      .to output(/.+/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
