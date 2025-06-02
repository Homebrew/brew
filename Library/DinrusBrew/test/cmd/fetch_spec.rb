# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe DinrusBrew::Cmd::FetchCmd do
  it_behaves_like "parseable arguments"

  it "downloads the Formula's URL", :integration_test do
    setup_test_formula "testball"

    expect { brew "fetch", "testball" }.to be_a_success

    expect(DINRUSBREW_CACHE/"testball--0.1.tbz").to be_a_symlink
    expect(DINRUSBREW_CACHE/"testball--0.1.tbz").to exist
  end
end
