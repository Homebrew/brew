# typed: true
# frozen_string_literal: true

require "lock_file"

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
      waiting = Queue.new
      # Release only once the blocking wait is about to start, so no `sleep` is needed.
      # Releasing from another thread also covers the wait staying outside `ignore_interrupts`.
      allow(download_lock_copy).to receive(:opoo).and_wrap_original do |original, *args|
        original.call(*args)
        waiting.push(true)
      end
      releaser = Thread.new do
        waiting.pop
        download_lock.unlock
      end

      expect { download_lock_copy.lock_or_wait }.to output(
        /Waiting for another Homebrew process to finish downloading/,
      ).to_stderr
      expect { download_lock.lock }.to raise_error(OperationInProgressError)
    ensure
      releaser&.join(5)
    end

    it "gives up and raises once the maximum wait time passes", timeout: 10 do
      stub_const("DownloadLock::MAX_WAIT_SECONDS", 0.25)
      download_lock.lock
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { download_lock_copy.lock_or_wait }.to raise_error(OperationInProgressError)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.25
    end

    it "retries until it locks the file that is on disk" do
      expect(download_lock.path).to receive(:exist?).twice.and_return(false, true)

      download_lock.lock_or_wait
    end
  end
end
