# typed: strict
# frozen_string_literal: true

module Utils
  # Gets the full commit hash of the HEAD commit.
  sig {
    params(
      repo:   T.any(String, Pathname),
      length: T.nilable(Integer),
      safe:   T::Boolean,
    ).returns(T.nilable(String))
  }
  def self.git_head(repo = Pathname.pwd, length: nil, safe: true)
    return git_short_head(repo, length:) if length

    GitRepository.new(Pathname(repo)).head_ref(safe:)
  end

  # Gets a short commit hash of the HEAD commit.
  sig {
    params(
      repo:   T.any(String, Pathname),
      length: T.nilable(Integer),
      safe:   T::Boolean,
    ).returns(T.nilable(String))
  }
  def self.git_short_head(repo = Pathname.pwd, length: nil, safe: true)
    GitRepository.new(Pathname(repo)).short_head_ref(length:, safe:)
  end

  # Gets the name of the currently checked-out branch, or HEAD if the repository is in a detached HEAD state.
  sig {
    params(
      repo: T.any(String, Pathname),
      safe: T::Boolean,
    ).returns(T.nilable(String))
  }
  def self.git_branch(repo = Pathname.pwd, safe: true)
    GitRepository.new(Pathname(repo)).branch_name(safe:)
  end

  # Gets the full commit message of the specified commit, or of the HEAD commit if unspecified.
  sig {
    params(
      repo:   T.any(String, Pathname),
      commit: String,
      safe:   T::Boolean,
    ).returns(T.nilable(String))
  }
  def self.git_commit_message(repo = Pathname.pwd, commit: "HEAD", safe: true)
    GitRepository.new(Pathname(repo)).commit_message(commit, safe:)
  end
end
