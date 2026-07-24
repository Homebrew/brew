# typed: strict
# frozen_string_literal: true

# Strategy for downloading a Git repository from GitHub.
#
# @api public
class GitHubGitDownloadStrategy < GitDownloadStrategy
  sig { returns(T.nilable(String)) }
  attr_reader :user

  sig { returns(T.nilable(String)) }
  attr_reader :repo

  sig { params(url: String, name: String, version: T.nilable(Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @version = version

    match_data = %r{^https?://github\.com/(?<user>[^/]+)/(?<repo>[^/]+)\.git$}.match(@url)
    return unless match_data

    @user = T.let(match_data[:user], T.nilable(String))
    @repo = T.let(match_data[:repo], T.nilable(String))
  end

  sig { override.returns(String) }
  def last_commit
    @last_commit ||= GitHub.last_commit(T.must(@user), T.must(@repo), @ref, T.cast(T.must(version), Version),
                                        length: MINIMUM_COMMIT_HASH_LENGTH)
    @last_commit || super
  end

  sig { override.params(commit: T.nilable(String)).returns(T::Boolean) }
  def commit_outdated?(commit)
    return true unless commit
    return super if last_commit.blank?
    return true unless last_commit.start_with?(commit)

    if GitHub.multiple_short_commits_exist?(T.must(@user), T.must(@repo), commit)
      true
    else
      T.must(@version).update_commit(commit)
      false
    end
  end

  sig { returns(String) }
  def default_refspec
    if default_branch
      "+refs/heads/#{default_branch}:refs/remotes/origin/#{default_branch}"
    else
      super
    end
  end

  sig { returns(T.nilable(String)) }
  def default_branch
    return @default_branch if defined?(@default_branch)

    command! "git",
             args:  ["remote", "set-head", "origin", "--auto"],
             chdir: cached_location

    result = command! "git",
                      args:  ["symbolic-ref", "refs/remotes/origin/HEAD"],
                      chdir: cached_location

    @default_branch = T.let(result.stdout[%r{^refs/remotes/origin/(.*)$}, 1], T.nilable(String))
  end
end
