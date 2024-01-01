# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew tap-info" do
  it_behaves_like "parseable arguments"

  it "gets information for a given Tap", :integration_test, :needs_network do
    setup_test_tap

    expect { brew "tap-info", "--json=v1", "--installed" }
      .to output(%r{https://github\.com/Homebrew/homebrew-foo}).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
