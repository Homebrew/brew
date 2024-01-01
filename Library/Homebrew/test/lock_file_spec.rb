# frozen_string_literal: true

require "lock_file"

describe LockFile do
  subject(:lock_file) { described_class.new("foo") }

  describe "#lock" do
    it "does not raise an error when already locked" do
      lock_file.lock

      expect { lock_file.lock }.not_to raise_error
    end

    it "raises an error if a lock already exists" do
      lock_file.lock

      expect do
        described_class.new("foo").lock
      end.to raise_error(OperationInProgressError)
    end
  end

  describe "#unlock" do
    it "does not raise an error when already unlocked" do
      expect { lock_file.unlock }.not_to raise_error
    end

    it "unlocks when locked" do
      lock_file.lock
      lock_file.unlock

      expect { described_class.new("foo").lock }.not_to raise_error
    end
  end
end
