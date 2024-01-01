# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew untap" do
  it_behaves_like "parseable arguments"

  it "untaps a given Tap", :integration_test do
    setup_test_tap

    expect { brew "untap", "homebrew/foo" }
      .to output(/Untapped/).to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end
end
