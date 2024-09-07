# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "fcntl"

# A lock file to prevent multiple Homebrew processes from modifying the same path.
class LockFile
  attr_reader :path

  sig { params(type: Symbol, locked_path: Pathname).void }
  def initialize(type, locked_path)
    @locked_path = locked_path
    lock_name = locked_path.basename.to_s
    @path = HOMEBREW_LOCKS/"#{lock_name}.#{type}.lock"
    @lockfile = nil
  end

  def lock
    @path.parent.mkpath
    create_lockfile
    return if @lockfile.flock(File::LOCK_EX | File::LOCK_NB)

    raise OperationInProgressError, @locked_path
  end

  def unlock
    return if @lockfile.nil? || @lockfile.closed?

    @lockfile.flock(File::LOCK_UN)
    @lockfile.close
  end

  def with_lock
    lock
    yield
  ensure
    unlock
  end

  private

  def create_lockfile
    return if @lockfile.present? && !@lockfile.closed?

    begin
      @lockfile = @path.open(File::RDWR | File::CREAT)
    rescue Errno::EMFILE
      odie "The maximum number of open files on this system has been reached. Use `ulimit -n` to increase this limit."
    end
    @lockfile.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
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
