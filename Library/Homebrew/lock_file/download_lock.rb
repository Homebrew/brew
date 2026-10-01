# typed: strict
# frozen_string_literal: true

# A lock file for a download.
class DownloadLock < LockFile
  MAX_WAIT_SECONDS = 180

  sig { params(download_path: Pathname).void }
  def initialize(download_path)
    super(:download, download_path)
  end

  # Waits for another process's download to finish instead of failing immediately.
  # `quiet:` suppresses the warning when the caller is already rendering its own
  # progress, since an unscheduled write desyncs `DownloadQueue`'s redraw.
  sig { params(quiet: T::Boolean, timeout: T.nilable(T.any(Integer, Float))).void }
  def lock_or_wait(quiet: false, timeout: nil)
    max_wait = MAX_WAIT_SECONDS
    max_wait = timeout if timeout && timeout < max_wait
    waiting_since = T.let(nil, T.nilable(Time))
    begin
      lock
    rescue OperationInProgressError
      if waiting_since.nil?
        waiting_since = Time.now
        opoo "Waiting for another Homebrew process to finish downloading #{locked_path}..." unless quiet
      end

      waited = Time.now - waiting_since
      raise OperationInProgressError.new(locked_path, waited: waited.round) if waited >= max_wait

      sleep 0.1
      retry
    end
  end
end
