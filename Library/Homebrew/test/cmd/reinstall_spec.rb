# frozen_string_literal: true

require "extend/ENV"
require "cmd/shared_examples/args_parse"

describe "brew reinstall" do
  it_behaves_like "parseable arguments"

  it "reinstalls a Formula", :integration_test do
    install_test_formula "testball"
    foo_dir = HOMEBREW_CELLAR/"testball/0.1/bin"
    expect(foo_dir).to exist
    foo_dir.rmtree

    expect { brew "reinstall", "testball" }
      .to output(/Reinstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    expect(foo_dir).to exist
  end
end
