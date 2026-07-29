# typed: strict
# frozen_string_literal: true

require "fcntl"
require "utils/output"

# A lock file to prevent multiple Homebrew processes from modifying the same path.
class LockFile
  include Utils::Output::Mixin

  sig { returns(Pathname) }
  attr_reader :path

  sig { returns(Pathname) }
  attr_reader :locked_path

  sig { params(type: Symbol, locked_path: Pathname).void }
  def initialize(type, locked_path)
    @locked_path = locked_path
    lock_name = locked_path.basename.to_s
    @path = T.let(HOMEBREW_LOCKS/"#{lock_name}.#{type}.lock", Pathname)
    @lockfile = T.let(nil, T.nilable(File))
  end

  # `blocking:` waits for the current holder to release rather than raising
  # `OperationInProgressError`. That wait is not wrapped in `ignore_interrupts`
  # (unlike the non-blocking path, which returns immediately) so `Ctrl-C` still
  # works while waiting.
  sig { params(blocking: T::Boolean).void }
  def lock(blocking: false)
    return if @lockfile.present?

    path.dirname.mkpath

    if blocking
      nil until acquired?(File::LOCK_EX)
    else
      ignore_interrupts { nil until acquired?(File::LOCK_EX | File::LOCK_NB) }
    end
  end

  sig { params(unlink: T::Boolean).void }
  def unlock(unlink: false)
    ignore_interrupts do
      next if @lockfile.nil?

      @path.unlink if unlink
      @lockfile.flock(File::LOCK_UN)
      @lockfile.close
      @lockfile = nil
    end
  end

  sig { params(_block: T.proc.void).void }
  def with_lock(&_block)
    lock
    yield
  ensure
    unlock
  end

  private

  # Returns false when the lock file changed on disk and must be reacquired.
  sig { params(flock_operation: Integer).returns(T::Boolean) }
  def acquired?(flock_operation)
    lockfile = open_lockfile

    unless lockfile.flock(flock_operation)
      lockfile.close
      raise OperationInProgressError, @locked_path
    end

    # This prevents a race condition in case the file we locked doesn't exist on disk anymore, e.g.:
    #
    # 1. Process A creates and opens the file.
    # 2. Process A locks the file.
    # 3. Process B opens the file.
    # 4. Process A unlinks the file.
    # 5. Process A unlocks the file.
    # 6. Process B locks the file.
    # 7. Process C creates and opens the file.
    # 8. Process C locks the file.
    # 9. Process B and C hold locks to files with different inode numbers. 💥
    if !path.exist? || lockfile.stat.ino != path.stat.ino
      lockfile.close
      return false
    end

    @lockfile = lockfile
    true
  end

  sig { returns(File) }
  def open_lockfile
    lockfile = begin
      File.open(path, File::RDWR | File::CREAT)
    rescue Errno::EMFILE
      odie "The maximum number of open files on this system has been reached. " \
           "Use `ulimit -n` to increase this limit."
    end
    lockfile.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    lockfile
  end
end
require "lock_file/formula_lock"
require "lock_file/cask_lock"
require "lock_file/download_lock"
