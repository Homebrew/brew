# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/tap"

RSpec.describe Homebrew::Cmd::TapCmd do
  it_behaves_like "parseable arguments"

  it "taps a given Tap", :integration_test do
    path = setup_test_tap

    expect { brew "tap", "homebrew/bar", path/".git" }
      .to output(/Tapped/).to_stderr
      .and be_a_success
  end
end
