# typed: strict
# frozen_string_literal: true

RSpec.describe Homebrew, :integration_test do
  it "does not require slow dependencies unnecessarily" do
    expect do
      brew "verify-undefined",
           "HOMEBREW_SORBET_RECURSIVE" => nil,
           "HOMEBREW_SORBET_RUNTIME"   => nil
    end
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
