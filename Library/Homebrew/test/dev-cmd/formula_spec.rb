# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew formula" do
  it_behaves_like "parseable arguments"

  it "prints a given Formula's path", :integration_test do
    formula_file = setup_test_formula "testball"

    expect { brew "formula", "testball" }
      .to output("#{formula_file}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
