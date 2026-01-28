# frozen_string_literal: true

require "extend/ENV"
require "cmd/reinstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Reinstall do
  it_behaves_like "parseable arguments"

  it "reinstalls a Formula", :aggregate_failures, :integration_test do
    formula_name = "testball_bottle"
    formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
    formula_bin = formula_prefix/"bin"

    setup_test_formula formula_name, tab_attributes: { installed_on_request: true }
    Keg.new(formula_prefix).link

    expect(formula_bin).not_to exist

    expect { brew "reinstall", formula_name }
      .to output(/Reinstalling #{formula_name}/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(formula_bin).to exist

    FileUtils.rm_r(formula_bin)

    expect { brew "reinstall", "--ask", formula_name }
      .to output(/.*Formula\s*\(1\):\s*#{formula_name}.*/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(formula_bin).to exist

    FileUtils.rm_r(formula_bin)

    expect { brew "reinstall", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
      .to not_to_output(/#{Regexp.escape(formula_prefix)}/o).to_stdout
      .and output(/#{formula_name} was forbidden/).to_stderr
      .and be_a_failure
    expect(formula_bin).not_to exist
  end
end
