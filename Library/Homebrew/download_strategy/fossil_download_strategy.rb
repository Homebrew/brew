# typed: strict
# frozen_string_literal: true

# Strategy for downloading a Fossil repository.
#
# @api public
class FossilDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^fossil://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    Time.parse(T.must(out[/^(hash|uuid): +\h+ (.+)$/, 2]))
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = last_commit.presence

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    T.must(out[/^(hash|uuid): +(\h+) .+$/, 2])
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    silent_command("fossil", args: ["branch", "-R", cached_location]).success?
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    { "PATH" => PATH.new(Formula["fossil"].opt_bin, ENV.fetch("PATH")) }
  end

  sig { override.returns(String) }
  def cache_tag
    "fossil"
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    command! "fossil", args: ["clone", @url, cached_location], timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "fossil", args: ["pull", "-R", cached_location], timeout: Utils::Timer.remaining(timeout)
  end
end
