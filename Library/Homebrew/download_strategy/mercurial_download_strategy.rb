# typed: strict
# frozen_string_literal: true

require "utils/timer"

# Strategy for downloading a Mercurial repository.
#
# @api public
class MercurialDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^hg://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    Time.parse(silent_command("hg", args: ["tip", "--template", "{date|isodate}", "-R", cached_location]).stdout)
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = current_revision.presence

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("hg", args: ["parent", "--template", "{node|short}", "-R", cached_location]).stdout.chomp
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    Utils::Path.formula_opt_bin_env("mercurial")
  end

  sig { override.returns(String) }
  def cache_tag
    "hg"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".hg").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    clone_args = %w[clone]

    case @ref_type
    when :branch
      clone_args << "--branch" << @ref
    when :revision, :tag
      clone_args << "--rev" << @ref
    end

    clone_args << @url << cached_location.to_s
    command! "hg", args: clone_args, timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    pull_args = %w[pull]

    case @ref_type
    when :branch
      pull_args << "--branch" << @ref
    when :revision, :tag
      pull_args << "--rev" << @ref
    end

    command! "hg", args: ["--cwd", cached_location, *pull_args], timeout: Utils::Timer.remaining(timeout)

    update_args = %w[update --clean]
    update_args << if @ref_type && @ref
      ohai "Checking out #{@ref_type} #{@ref}"
      @ref
    else
      "default"
    end

    command! "hg", args: ["--cwd", cached_location, *update_args], timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.returns(String) }
  def current_revision
    silent_command("hg", args: ["--cwd", cached_location, "identify", "--id"]).stdout.strip
  end
end
