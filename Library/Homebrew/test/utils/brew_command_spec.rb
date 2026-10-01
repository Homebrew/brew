# typed: strict
# frozen_string_literal: true

require "utils/brew_command"

RSpec.describe Utils::BrewCommand do
  describe ".run!" do
    it "runs the current brew executable" do
      expect(SystemCommand).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "install", "testball")

      described_class.run!("install", "testball")
    end
  end
end
