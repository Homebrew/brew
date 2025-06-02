# frozen_string_literal: true

require "cmd/docs"
require "cmd/shared_examples/args_parse"

RSpec.describe DinrusBrew::Cmd::Docs do
  it_behaves_like "parseable arguments"

  it "opens the docs page", :integration_test do
    expect { brew "docs", "DINRUSBREW_BROWSER" => "echo" }
      .to output("https://docs.brew.sh\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
