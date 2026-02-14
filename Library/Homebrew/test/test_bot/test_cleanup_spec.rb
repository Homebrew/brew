# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::TestCleanup do
  # Regression test: checkout_branch_if_needed, reset_if_needed, and clean_if_needed
  # expect a String (repository path). Passing HOMEBREW_REPOSITORY (Pathname) causes
  # "Parameter 'repository': Expected type String, got type Pathname" in strict typing.
  describe "cleanup_shared" do
    it "passes a String to checkout_branch_if_needed, reset_if_needed, and clean_if_needed when tap is set" do
      cleanup = described_class.new(
        tap:       CoreTap.instance,
        git:       "git",
        dry_run:   false,
        fail_fast: false,
        verbose:   false,
      )

      # Stub so we reach the "if tap" block without running git or deleting files.
      allow(cleanup).to receive(:repository).and_return(Pathname.new("/nonexistent_brew_repo_#{SecureRandom.hex(8)}"))
      allow(cleanup).to receive(:info_header)
      allow(cleanup).to receive(:delete_or_move)
      allow(Keg).to receive(:must_be_writable_directories).and_return([])
      allow(Pathname).to receive(:glob).and_return([])
      allow(cleanup).to receive(:test)

      expect(cleanup).to receive(:checkout_branch_if_needed).with(String)
      expect(cleanup).to receive(:reset_if_needed).with(String)
      expect(cleanup).to receive(:clean_if_needed).with(String)

      cleanup.send(:cleanup_shared)
    end
  end
end
