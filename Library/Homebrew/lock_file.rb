# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "fcntl"

# A lock file to prevent multiple Homebrew processes from modifying the same path.
class LockFile
  class OpenFileChangedOnDisk < RuntimeError; end
  private_constant :OpenFileChangedOnDisk

  attr_reader :path

  sig { params(type: Symbol, locked_path: Pathname).void }
  def initialize(type, locked_path)
    @locked_path = locked_path
    lock_name = locked_path.basename.to_s
    @path = HOMEBREW_LOCKS/"#{lock_name}.#{type}.lock"
    @lockfile = nil
  end

  sig { void }
  def lock
    ignore_interrupts do
      next if @lockfile.present?

      path.dirname.mkpath

      begin
        lockfile = begin
          path.open(File::RDWR | File::CREAT)
        rescue Errno::EMFILE
          odie "The maximum number of open files on this system has been reached. " \
               "Use `ulimit -n` to increase this limit."
        end
        lockfile.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

        if lockfile.flock(File::LOCK_EX | File::LOCK_NB)
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
            raise OpenFileChangedOnDisk
          end

          @lockfile = lockfile
          next
        end
      rescue OpenFileChangedOnDisk
        retry
      end

      lockfile.close
      raise OperationInProgressError, @locked_path
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

  def with_lock
    lock
    yield
  ensure
    unlock
  end
end

# A lock file for a formula.
class FormulaLock < LockFile
  sig { params(rack_name: String).void }
  def initialize(rack_name)
    super(:formula, HOMEBREW_CELLAR/rack_name)
  end
end

# A lock file for a cask.
class CaskLock < LockFile
  sig { params(cask_token: String).void }
  def initialize(cask_token)
    super(:cask, HOMEBREW_PREFIX/"Caskroom/#{cask_token}")
  end
end

# A lock file for a download.
class DownloadLock < LockFile
  sig { params(download_path: Pathname).void }
  def initialize(download_path)
    super(:download, download_path)
  end
end
