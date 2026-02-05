# frozen_string_literal: true

require "cmd/desc"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Desc do
  it_behaves_like "parseable arguments"

  it "shows a given Formula's description", :integration_test do
    setup_test_formula "testball"

    expect { brew "desc", "testball" }
      .to output("testball: Some test\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "errors when searching without --eval-all", :integration_test, :no_api do
    setup_test_formula "testball"

    expect { brew "desc", "--search", "testball" }
      .to output(/`brew desc --search` needs `--eval-all` passed or `HOMEBREW_EVAL_ALL=1` set!/).to_stderr
      .and be_a_failure
  end

  it "successfully searches with --search --eval-all", :integration_test, :no_api do
    setup_test_formula "testball"

    expect { brew "desc", "--search", "--eval-all", "ball" }
      .to output(/testball: Some test/).to_stdout
      .and not_to_output.to_stderr
  end

  it "successfully searches without --eval-all, with API", :integration_test, :needs_network do
    setup_test_formula "testball"

    expect { brew "desc", "--search", "testball" }.to be_a_success
  end
end
