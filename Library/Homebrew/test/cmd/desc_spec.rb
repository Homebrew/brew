# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew desc" do
  it_behaves_like "parseable arguments"

  it "shows a given Formula's description", :integration_test do
    setup_test_formula "testball"

    expect { brew "desc", "--eval-all", "testball" }
      .to output("testball: Some test\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
