# typed: strict
# frozen_string_literal: true

require "utils/timer"

# Strategy for downloading a CVS repository.
#
# @api public
class CVSDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^cvs://}, ""), String)

    @module = T.let(
      if meta.key?(:module)
        meta.fetch(:module)
      elsif !@url.match?(%r{:[^/]+$})
        name
      else
        mod, url = split_url(@url)
        @url = T.let(url, String)
        mod
      end, String
    )
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    # Filter CVS's files because the timestamp for each of them is the moment
    # of clone.
    max_mtime = Time.at(0)
    cached_location.find do |f|
      Find.prune if f.directory? && f.basename.to_s == "CVS"
      next unless f.file?

      mtime = f.mtime
      max_mtime = mtime if mtime > max_mtime
    end
    max_mtime
  end

  private

  sig { override.params(sandbox: Sandbox).void }
  def allow_fetch_credentials(sandbox)
    # Only pserver uses `cvs login`, which writes the password cache read by checkout/update.
    return if @url.exclude?("pserver")

    sandbox.allow_read(path: password_file)
    sandbox.allow_write(path: password_file)
  end

  # Keep using the user's password cache when the sandbox replaces HOME.
  sig { returns(Pathname) }
  def password_file
    Pathname(ENV.fetch("CVS_PASSFILE") { "#{Dir.home}/.cvspass" }).expand_path
  end

  sig { override.returns(T::Hash[String, String]) }
  def env
    { "PATH"         => PATH.new("/usr/bin", Utils::Path.formula_opt_bin_path("cvs")).to_s,
      "CVS_PASSFILE" => password_file.to_s }
  end

  sig { override.returns(String) }
  def cache_tag
    "cvs"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/"CVS").directory?
  end

  sig { returns(T.nilable(String)) }
  def quiet_flag
    "-Q" unless verbose?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    # Login is only needed (and allowed) with pserver; skip for anoncvs.
    if @url.include? "pserver"
      command! "cvs", args:    [*quiet_flag, "-d", @url, "login"],
                      timeout: Utils::Timer.remaining(timeout)
    end

    command! "cvs",
             args:    [*quiet_flag, "-d", @url, "checkout", "-d", basename.to_s, @module],
             chdir:   cached_location.dirname,
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "cvs",
             args:    [*quiet_flag, "update"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { params(in_url: String).returns([String, String]) }
  def split_url(in_url)
    parts = in_url.split(":")
    mod = parts.pop
    raise ArgumentError, "CVS URL #{in_url.inspect} does not end with a module name" if mod.nil?

    url = parts.join(":")
    [mod, url]
  end
end
