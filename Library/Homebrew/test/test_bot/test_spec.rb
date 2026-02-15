# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::Test do
  describe "#test" do
    it "converts Pathname arguments to strings" do
      # Regression test: callers like TestCleanup pass Pathname objects (e.g. repository)
      # as positional arguments. The `test` method must coerce them to String before
      # forwarding to Step.new, which expects T::Array[String].
      test_instance = described_class.new(dry_run: true)

      step = test_instance.send(:test, "git", "-C", Pathname.new("/some/path"), "status")

      expect(step.command).to eq(["git", "-C", "/some/path", "status"])
      expect(step).to be_passed
    end
  end
end
