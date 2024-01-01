# frozen_string_literal: true

require "cmd/search"
require "cmd/shared_examples/args_parse"

describe "brew search" do
  it_behaves_like "parseable arguments"

  it "finds formula in search", :integration_test do
    setup_test_formula "testball"

    expect { brew "search", "testball" }
      .to output(/testball/).to_stdout
      .and be_a_success
  end
end
