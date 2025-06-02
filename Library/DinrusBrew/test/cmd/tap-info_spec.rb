# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/tap-info"

RSpec.describe DinrusBrew::Cmd::TapInfo do
  it_behaves_like "parseable arguments"

  it "gets information for a given Tap", :integration_test, :needs_network do
    setup_test_tap

    expect { brew "tap-info", "--json=v1", "--installed" }
      .to output(%r{https://github\.com/DinrusBrew/homebrew-foo}).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "display brief statistics for all installed taps", :integration_test, :needs_network do
    expect { brew "tap-info", "DINRUSBREW_NO_INSTALL_FROM_API" => nil }
      .to output(/\d+ taps?, \d+ private/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
