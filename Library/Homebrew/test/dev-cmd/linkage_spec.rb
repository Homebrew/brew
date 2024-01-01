# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew linkage" do
  it_behaves_like "parseable arguments"

  it "works when no arguments are provided", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "linkage" }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end
end
