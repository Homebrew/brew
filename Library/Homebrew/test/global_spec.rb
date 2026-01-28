# frozen_string_literal: true

RSpec.describe Homebrew, :integration_test do
  it "does not require slow dependencies at startup" do
    expect { brew "verify-undefined" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
