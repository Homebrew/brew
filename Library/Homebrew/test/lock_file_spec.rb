# frozen_string_literal: true

require "lock_file"

RSpec.describe LockFile do
  subject(:lock_file) { described_class.new(:lock, Pathname("foo")) }

  let(:lock_file_copy) { described_class.new(:lock, Pathname("foo")) }

  describe "#lock" do
    it "ensures the lock file is created" do
      expect(lock_file.path).not_to exist
      lock_file.lock
      expect(lock_file.path).to exist
    end

    it "does not raise an error when the same instance is locked multiple times" do
      lock_file.lock

      expect { lock_file.lock }.not_to raise_error
    end

    it "raises an error if another instance is already locked" do
      lock_file.lock

      expect do
        lock_file_copy.lock
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

      expect { lock_file_copy.lock }.not_to raise_error
    end

    it "allows deleting a lock file only by the instance that locked it" do
      lock_file.lock
      expect(lock_file.path).to exist

      expect(lock_file_copy.path).to exist
      lock_file_copy.unlock(unlink: true)
      expect(lock_file_copy.path).to exist
      expect(lock_file.path).to exist

      lock_file.unlock(unlink: true)
      expect(lock_file.path).not_to exist
    end
  end
end
