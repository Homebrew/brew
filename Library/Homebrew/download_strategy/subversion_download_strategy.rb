# typed: strict
# frozen_string_literal: true

# Strategy for downloading a Subversion repository.
#
# @api public
class SubversionDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = @url.sub("svn+http://", "")
  end

  # Download and cache the repository at {#cached_location}.
  #
  # @api public
  sig { override.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil)
    if @url.chomp("/") != repo_url || !silent_command("svn", args: ["switch", @url, cached_location]).success?
      clear_cache
    end
    super
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    require "utils/svn"

    time = if Version.new(T.must(Utils::Svn.version)) >= Version.new("1.9")
      silent_command("svn", args: ["info", "--show-item", "last-changed-date"], chdir: cached_location).stdout
    else
      silent_command("svn", args: ["info"], chdir: cached_location).stdout[/^Last Changed Date: (.+)$/, 1]
    end
    Time.parse T.must(time)
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = last_commit

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("svn", args: ["info", "--show-item", "revision"], chdir: cached_location).stdout.strip
  end

  private

  sig { returns(T.nilable(String)) }
  def repo_url
    silent_command("svn", args: ["info"], chdir: cached_location).stdout.strip[/^URL: (.+)$/, 1]
  end

  sig { params(_block: T.proc.params(arg0: String, arg1: String).void).void }
  def externals(&_block)
    out = silent_command("svn", args: ["propget", "svn:externals", @url]).stdout
    out.chomp.split("\n").each do |line|
      name, url = line.split(/\s+/)
      yield T.must(name), T.must(url)
    end
  end

  sig {
    params(target: Pathname, url: String, revision: T.nilable(String), ignore_externals: T::Boolean,
           timeout: T.nilable(Time)).void
  }
  def fetch_repo(target, url, revision = nil, ignore_externals: false, timeout: nil)
    # Use "svn update" when the repository already exists locally.
    # This saves on bandwidth and will have a similar effect to verifying the
    # cache as it will make any changes to get the right revision.
    args = []
    args << "--quiet" unless verbose?

    if revision
      ohai "Checking out #{@ref}"
      args << "-r" << revision
    end

    args << "--ignore-externals" if ignore_externals

    require "utils/svn"
    args.concat Utils::Svn.invalid_cert_flags if meta[:trust_cert] == true

    if target.directory?
      command! "svn", args: ["update", *args], chdir: target.to_s, timeout: Utils::Timer.remaining(timeout)
    else
      command! "svn", args: ["checkout", *args, "--", url, target], timeout: Utils::Timer.remaining(timeout)
    end
  end

  sig { override.returns(String) }
  def cache_tag
    head? ? "svn-HEAD" : "svn"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".svn").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    case @ref_type
    when :revision
      fetch_repo cached_location, @url, @ref, timeout:
    when :revisions
      # nil is OK for main_revision, as fetch_repo will then get latest
      main_revision = @ref[:trunk]
      fetch_repo(cached_location, @url, main_revision, ignore_externals: true, timeout:)

      externals do |external_name, external_url|
        fetch_repo cached_location/external_name, external_url, @ref[external_name], ignore_externals: true,
                                                                                     timeout:
      end
    else
      fetch_repo cached_location, @url, timeout:
    end
  end
  alias update clone_repo
end
