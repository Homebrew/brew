# typed: strict
# frozen_string_literal: true

# A lock file for a download.
class DownloadLock < LockFile
  # Long enough for even a large download on a slow connection, short enough to eventually
  # give up and report the original error if the holder is genuinely stuck.
  MAX_WAIT_SECONDS = 3600

  sig { params(download_path: Pathname).void }
  def initialize(download_path)
    super(:download, download_path)
  end

  # Waits for another process's download to finish instead of failing immediately.
  sig { void }
  def lock_or_wait
    lock
  rescue OperationInProgressError
    require "timeout"

    opoo "Waiting for another Homebrew process to finish downloading #{locked_path}..."
    begin
      Timeout.timeout(MAX_WAIT_SECONDS) { lock(blocking: true) }
    rescue Timeout::Error
      raise OperationInProgressError, locked_path
    end
  end
end
