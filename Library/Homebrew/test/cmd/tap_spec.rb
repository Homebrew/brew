# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew tap" do
  it_behaves_like "parseable arguments"

  it "taps a given Tap", :integration_test do
    path = setup_test_tap

    expect { brew "tap", "--force-auto-update", "homebrew/bar", path/".git" }
      .to output(/Tapped/).to_stderr
      .and be_a_success
  end
end
