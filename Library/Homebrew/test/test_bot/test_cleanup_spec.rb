# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::CleanupAfter do
  # Regression test: checkout_branch_if_needed, reset_if_needed, and clean_if_needed
  # expect a String (repository path). Passing HOMEBREW_REPOSITORY (Pathname) would cause
  # "Parameter 'repository': Expected type String, got type Pathname" in strict typing.
  describe "#run!" do
    it "passes a String to checkout_branch_if_needed, reset_if_needed, and clean_if_needed when tap is set" do
      cleanup = described_class.new(
        tap:       CoreTap.instance,
        git:       "git",
        dry_run:   true,
        fail_fast: false,
        verbose:   false,
      )

      # Stub to avoid actual filesystem and process operations.
      allow(FileUtils).to receive(:chmod_R)
      allow(cleanup).to receive(:info_header)
      allow(cleanup).to receive(:delete_or_move)
      allow(cleanup).to receive(:test)
      allow(cleanup).to receive_messages(repository:   Pathname.new("/nonexistent_#{SecureRandom.hex(8)}"),
                                         quiet_system: false)
      allow(Keg).to receive(:must_be_writable_directories).and_return([])
      allow(Pathname).to receive(:glob).and_return([])

      expect(cleanup).to receive(:checkout_branch_if_needed).with(String)
      expect(cleanup).to receive(:reset_if_needed).with(String)
      expect(cleanup).to receive(:clean_if_needed).with(String)

      args = double(test_default_formula?: false, local?: false)
      with_env("HOMEBREW_GITHUB_ACTIONS" => nil, "GITHUB_ACTIONS" => nil) do
        cleanup.run!(args:)
      end
    end
  end
end
