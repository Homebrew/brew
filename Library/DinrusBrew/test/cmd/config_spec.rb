# frozen_string_literal: true

require "cmd/config"
require "cmd/shared_examples/args_parse"

RSpec.describe DinrusBrew::Cmd::Config do
  it_behaves_like "parseable arguments"

  it "prints information about the current DinrusBrew configuration", :integration_test do
    expect { brew "config" }
      .to output(/DINRUSBREW_VERSION: #{Regexp.escape DINRUSBREW_VERSION}/o).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
