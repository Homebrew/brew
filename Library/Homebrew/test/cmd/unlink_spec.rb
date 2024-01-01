# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew unlink" do
  it_behaves_like "parseable arguments"

  it "unlinks a Formula", :integration_test do
    install_test_formula "testball"

    expect { brew "unlink", "testball" }
      .to output(/Unlinking /).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
