# typed: strict
# frozen_string_literal: true

require "utils/timer"

# Strategy for downloading a Fossil repository.
#
# @api public
class FossilDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^fossil://}, ""), String)
    # Keep SQLite journals writable without granting writes to the whole cache.
    @cached_location = Pathname("#{cached_location}-sandbox")/"repository.fossil"
  end

  sig { override.returns(Pathname) }
  def sandbox_write_path = cached_location.dirname

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    modified_time = out[/^(?:hash|uuid): +\h+ (.+)$/, 1]
    raise "Could not parse the modification time from `fossil info tip` for #{cached_location}" if modified_time.nil?

    Time.parse(modified_time)
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = last_commit.presence

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    commit = out[/^(?:hash|uuid): +(\h+) .+$/, 1]
    raise "Could not parse the commit hash from `fossil info tip` for #{cached_location}" if commit.nil?

    commit
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    silent_command("fossil", args: ["branch", "-R", cached_location]).success?
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    Utils::Path.formula_opt_bin_env("fossil")
  end

  sig { override.returns(String) }
  def cache_tag
    "fossil"
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    cached_location.dirname.mkpath
    command! "fossil", args: ["clone", @url, cached_location], timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "fossil", args: ["pull", "-R", cached_location], timeout: Utils::Timer.remaining(timeout)
  end
end
