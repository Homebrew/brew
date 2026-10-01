# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/formula"

RSpec.describe Homebrew::DevCmd::FormulaCmd do
  it_behaves_like "parseable arguments"

  it "prints a given Formula's path", :integration_test do
    formula_file = Formulary.find_formula_in_tap("testball", CoreTap.instance)
    formula_file.dirname.mkpath
    formula_file.write ""

    expect { brew "formula", "testball" }
      .to output("#{formula_file}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
