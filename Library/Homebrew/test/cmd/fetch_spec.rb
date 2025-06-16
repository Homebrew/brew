# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::FetchCmd do
  it_behaves_like "parseable arguments"

  it "downloads the Formula's URL", :integration_test do
    setup_test_formula "testball"

    expect { brew "fetch", "testball" }.to be_a_success

    expect(HOMEBREW_CACHE/"testball--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball--0.1.tbz").to exist
  end

  it "concurrently downloads formula URLs", :integration_test do
    setup_test_formula "testball1"
    setup_test_formula "testball2"

    expect { brew "fetch", "testball1", "testball2", "--concurrency=2" }.to be_a_success

    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to exist
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to exist
  end

  it "errors when concurrently downloading to the same destination", :integration_test do
    # This test will fail if the fetch is not performed concurrently.
    # N.B. this test relies on how we set up test formulae, see the `integration_test` shared context.
    setup_test_formula "testball1"
    setup_test_formula "testball3"

    expect { brew "fetch", "testball1", "testball3", "--concurrency=2" }.to be_a_failure
      .and output(/Error:.*process has already locked/).to_stderr
  end
end
