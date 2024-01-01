# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew missing" do
  it_behaves_like "parseable arguments"

  it "prints missing dependencies", :integration_test do
    setup_test_formula "foo"
    setup_test_formula "bar"

    (HOMEBREW_CELLAR/"bar/1.0").mkpath

    expect { brew "missing" }
      .to output("foo\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_failure
  end
end
