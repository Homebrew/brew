# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

RSpec.describe "DinrusBrew::Cmd::Services", :integration_test, :needs_network do
  before { setup_remote_tap "homebrew/services" }

  it_behaves_like "parseable arguments", command_name: "services"

  it "allows controlling services" do
    expect { brew "services", "list" }
      .to not_to_output.to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end
end
