# typed: strict
# frozen_string_literal: true

require "utils/timer"

# Strategy for downloading a Bazaar repository.
#
# @api public
class BazaarDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^bzr://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    timestamp = silent_command("bzr", args: ["log", "-l", "1", "--timezone=utc", cached_location]).stdout.chomp
    raise "Could not get any timestamps from bzr!" if timestamp.blank?

    Time.parse(timestamp)
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = last_commit.presence

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("bzr", args: ["revno", cached_location]).stdout.chomp
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    Utils::Path.formula_opt_bin_env("breezy").tap do |env|
      # BZR_HOME takes precedence over the sandbox's private HOME.
      env["BZR_HOME"] = HOMEBREW_TEMP.to_s unless Sandbox.isolate_operation?
    end
  end

  sig { override.returns(String) }
  def cache_tag
    "bzr"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".bzr").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    # "lightweight" means history-less
    command! "bzr",
             args:    ["checkout", "--lightweight", @url, cached_location],
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "bzr",
             args:    ["update"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
  end
end
