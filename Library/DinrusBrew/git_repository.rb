# typed: strict
# frozen_string_literal: true

require "utils/git"
require "utils/popen"

# Given a {Pathname}, provides methods for querying Git repository information.
# @see Utils::Git
class GitRepository
  sig { returns(Pathname) }
  attr_reader :pathname

  sig { params(pathname: Pathname).void }
  def initialize(pathname)
    @pathname = pathname
  end

  sig { returns(T::Boolean) }
  def git_repository?
    pathname.join(".git").exist?
  end

  sig { returns(T::Boolean) }
  def git_repo?
    # delete this whole function when removing odisabled
    odeprecated "GitRepository#git_repo?", "GitRepository#git_repository?"
    git_repository?
  end

  # Gets the URL of the Git origin remote.
  sig { returns(T.nilable(String)) }
  def origin_url
    popen_git("config", "--get", "remote.origin.url")
  end

  # Sets the URL of the Git origin remote.
  sig { params(origin: String).returns(T.nilable(T::Boolean)) }
  def origin_url=(origin)
    return if !git_repository? || !Utils::Git.available?

    safe_system Utils::Git.git, "remote", "set-url", "origin", origin, chdir: pathname
  end

  # Gets the full commit hash of the HEAD commit.
  sig { params(safe: T::Boolean).returns(T.nilable(String)) }
  def head_ref(safe: false)
    popen_git("rev-parse", "--verify", "--quiet", "HEAD", safe:)
  end

  # Gets a short commit hash of the HEAD commit.
  sig { params(length: T.nilable(Integer), safe: T::Boolean).returns(T.nilable(String)) }
  def short_head_ref(length: nil, safe: false)
    short_arg = length.present? ? "--short=#{length}" : "--short"
    popen_git("rev-parse", short_arg, "--verify", "--quiet", "HEAD", safe:)
  end

  # Gets the relative date of the last commit, e.g. "1 hour ago"
  sig { returns(T.nilable(String)) }
  def last_committed
    popen_git("show", "-s", "--format=%cr", "HEAD")
  end

  # Gets the name of the currently checked-out branch, or HEAD if the repository is in a detached HEAD state.
  sig { params(safe: T::Boolean).returns(T.nilable(String)) }
  def branch_name(safe: false)
    popen_git("rev-parse", "--abbrev-ref", "HEAD", safe:)
  end

  # Change the name of a local branch
  sig { params(old: String, new: String).void }
  def rename_branch(old:, new:)
    popen_git("branch", "-m", old, new)
  end

  # Set an upstream branch for a local branch to track
  sig { params(local: String, origin: String).void }
  def set_upstream_branch(local:, origin:)
    popen_git("branch", "-u", "origin/#{origin}", local)
  end

  # Gets the name of the default origin HEAD branch.
  sig { returns(T.nilable(String)) }
  def origin_branch_name
    popen_git("symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")&.split("/")&.last
  end

  # Returns true if the repository's current branch matches the default origin branch.
  sig { returns(T.nilable(T::Boolean)) }
  def default_origin_branch?
    origin_branch_name == branch_name
  end

  # Returns the date of the last commit, in YYYY-MM-DD format.
  sig { returns(T.nilable(String)) }
  def last_commit_date
    popen_git("show", "-s", "--format=%cd", "--date=short", "HEAD")
  end

  # Returns true if the given branch exists on origin
  sig { params(branch: String).returns(T::Boolean) }
  def origin_has_branch?(branch)
    popen_git("ls-remote", "--heads", "origin", branch).present?
  end

  sig { void }
  def set_head_origin_auto
    popen_git("remote", "set-head", "origin", "--auto")
  end

  # Gets the full commit message of the specified commit, or of the HEAD commit if unspecified.
  sig { params(commit: String, safe: T::Boolean).returns(T.nilable(String)) }
  def commit_message(commit = "HEAD", safe: false)
    popen_git("log", "-1", "--pretty=%B", commit, "--", safe:, err: :out)&.strip
  end

  sig { returns(String) }
  def to_s = pathname.to_s

  private

  sig { params(args: T.untyped, safe: T::Boolean, err: T.nilable(Symbol)).returns(T.nilable(String)) }
  def popen_git(*args, safe: false, err: nil)
    unless git_repository?
      return unless safe

      raise "Not a Git repository: #{pathname}"
    end

    unless Utils::Git.available?
      return unless safe

      raise "Git is unavailable"
    end

    Utils.popen_read(Utils::Git.git, *args, safe:, chdir: pathname, err:).chomp.presence
  end
end
