# frozen_string_literal: true

require "cmd/pin"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Pin do
  it_behaves_like "parseable arguments"

  it "pins a Formula's version", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect { brew "pin", "testball" }.to be_a_success
  end

  it "fails with an uninstalled Formula", :integration_test do
    setup_test_formula "testball"

    expect { brew "pin", "testball" }.to be_a_failure
  end
end
