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

    it "waits for another instance's lock to release, then acquires it" do
      download_lock.lock
      allow(download_lock_copy).to receive(:sleep) { download_lock.unlock }

      expect { download_lock_copy.lock_or_wait }.not_to raise_error
    end

    it "retries until the other instance's lock is released" do
      download_lock.lock
      attempts = 0
      allow(download_lock_copy).to receive(:sleep) do
        attempts += 1
        download_lock.unlock if attempts >= 3
      end

      download_lock_copy.lock_or_wait

      expect(attempts).to eq(3)
    end

    it "warns only once no matter how many attempts it takes" do
      download_lock.lock
      attempts = 0
      allow(download_lock_copy).to receive(:sleep) do
        attempts += 1
        download_lock.unlock if attempts >= 3
      end

      expect(download_lock_copy).to receive(:opoo).once.with(
        /Waiting for another Homebrew process to finish downloading/,
      ).and_call_original

      download_lock_copy.lock_or_wait
    end

    it "stays silent while waiting when quiet" do
      download_lock.lock
      allow(download_lock_copy).to receive(:sleep) { download_lock.unlock }

      expect { download_lock_copy.lock_or_wait(quiet: true) }.not_to output.to_stderr
    end

    it "gives up and raises the original error once the maximum wait time passes" do
      stub_const("DownloadLock::MAX_WAIT_SECONDS", 0)
      download_lock.lock
      allow(download_lock_copy).to receive(:sleep)

      expect { download_lock_copy.lock_or_wait(quiet: true) }.to raise_error(OperationInProgressError)
    end

    it "reports how long it waited when giving up" do
      stub_const("DownloadLock::MAX_WAIT_SECONDS", 0)
      download_lock.lock
      allow(download_lock_copy).to receive(:sleep)

      expect do
        download_lock_copy.lock_or_wait(quiet: true)
      end.to raise_error(/Gave up after waiting \d+ seconds/)
    end

    it "waits no longer than the caller's remaining time", timeout: 5 do
      download_lock.lock
      allow(download_lock_copy).to receive(:sleep)

      expect do
        download_lock_copy.lock_or_wait(quiet: true, timeout: 0)
      end.to raise_error(OperationInProgressError)
    end
  end
end
