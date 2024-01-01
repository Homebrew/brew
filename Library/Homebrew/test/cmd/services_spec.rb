# frozen_string_literal: true

describe "brew services", :integration_test, :needs_network do
  it "allows controlling services" do
    setup_remote_tap "homebrew/services"

    expect { brew "services", "list" }
      .to not_to_output.to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end
end
