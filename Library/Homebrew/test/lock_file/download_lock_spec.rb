# typed: true
# frozen_string_literal: true

require "lock_file/download_lock"

RSpec.describe DownloadLock do
  subject(:download_lock) { described_class.new(Pathname("foo-download")) }

  let(:download_lock_copy) { described_class.new(Pathname("foo-download")) }

  after do
    download_lock.unlock
    download_lock_copy.unlock
  end

  describe "#lock_or_wait" do
    it "acquires the lock immediately when uncontended" do
      expect { download_lock.lock_or_wait }.not_to raise_error
    end

    it "waits for another instance's lock to release, then acquires it", timeout: 10 do
      download_lock.lock
      releaser = Thread.new do
        sleep 0.2
        download_lock.unlock
      end

      expect { download_lock_copy.lock_or_wait }.to output(
        /Waiting for another Homebrew process to finish downloading/,
      ).to_stderr
    ensure
      releaser&.join(5)
    end

    it "gives up and raises once the maximum wait time passes", timeout: 10 do
      stub_const("DownloadLock::MAX_WAIT_SECONDS", 0.1)
      download_lock.lock

      expect { download_lock_copy.lock_or_wait }.to raise_error(OperationInProgressError)
    end
  end
end
