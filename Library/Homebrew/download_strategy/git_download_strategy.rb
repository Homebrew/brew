# typed: strict
# frozen_string_literal: true

require "utils/timer"

# Strategy for downloading a Git repository.
#
# @api public
class GitDownloadStrategy < VCSDownloadStrategy
  MINIMUM_COMMIT_HASH_LENGTH = 7

  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    # Needs to be before the call to `super`, as the VCSDownloadStrategy's
    # constructor calls `cache_tag` and sets the cache path.
    @only_path = meta[:only_path]

    if @only_path.present?
      # "Cone" mode of sparse checkout requires patterns to be directories
      @only_path = T.let("/#{@only_path}", String) unless @only_path.start_with?("/")
      @only_path = T.let("#{@only_path}/", String) unless @only_path.end_with?("/")
    end

    super
    @ref_type ||= T.let(:branch, T.nilable(Symbol))
    @ref ||= T.let("master", T.untyped)
  end

  sig { override.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil)
    require "utils/git"
    Utils::Git.ensure_installed!
    super
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    result = system_command("git", args: ["--git-dir", git_dir, "show", "-s", "--format=%cD"],
                                   env:  local_git_env, print_stderr: false)
    raise "Failed to read the Git commit time:\n#{result.stderr}" unless result.success?

    Time.parse(result.stdout)
  end

  sig { override.returns(T.nilable(String)) }
  def source_revision = current_revision.presence

  # Return last commit's unique identifier for the repository if fetched locally.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    args = ["--git-dir", git_dir, "rev-parse", "--short=#{MINIMUM_COMMIT_HASH_LENGTH}", "HEAD"]
    @last_commit ||= system_command("git", args:, env: local_git_env, print_stderr: false).stdout.chomp.presence
    @last_commit || ""
  end

  sig { returns(T::Boolean) }
  def ref?
    silent_command("git",
                   args: ["--git-dir", git_dir, "rev-parse", "-q", "--verify", "--end-of-options",
                          "#{@ref}^{commit}"])
      .success?
  end

  sig { returns(T::Array[String]) }
  def clone_args
    args = %w[clone]

    case @ref_type
    when :branch, :tag
      args << "--branch" << @ref
    end

    args << "--no-checkout" << "--filter=blob:none" if partial_clone_sparse_checkout?

    args << "--config" << "advice.detachedHead=false" # Silences “detached head” warning.
    args << "--config" << "core.fsmonitor=false" # Prevent `fsmonitor` from watching this repository.
    args << "--end-of-options" << @url << cached_location.to_s
  end

  private

  sig { override.returns(Symbol) }
  def fetch_home_read_exception = :git

  sig { override.params(sandbox: Sandbox).void }
  def allow_fetch_credentials(sandbox)
    # Let Git and SSH resolve configuration, includes, URL rewrites and agent sockets.
    sandbox.allow_network(path: "/", type: :subpath)
  end

  # Read user Git config so credential helpers work for private downloads,
  # but never block on an interactive credential prompt.
  sig { override.returns(T::Hash[String, String]) }
  def env
    { "GIT_TERMINAL_PROMPT" => "0" }.tap do |env|
      if fetching? && Sandbox.isolate_operation?
        env["HOME"] = Dir.home(ENV.fetch("USER"))
        env["PATH"] = PATH.new(ENV.fetch("PATH"), ORIGINAL_PATHS).to_s
        env["SSH_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS_REQUIRE"] = "force"
        if (socket = ENV.fetch("SSH_AUTH_SOCK", nil))
          env["SSH_AUTH_SOCK"] = socket
        end
      end
      next if !fetching? || !(token = Homebrew::EnvConfig.github_api_token) || !which("gh", ORIGINAL_PATHS)

      env["PATH"] ||= PATH.new(ENV.fetch("PATH"), ORIGINAL_PATHS).to_s
      # Resolve rewrites and helpers with the same configuration Git will use.
      git_options = { env:, chdir: cached_location.directory? ? cached_location : HOMEBREW_CACHE,
                      print_stderr: false }
      remote = system_command("git", args: ["ls-remote", "--get-url", "--", url], **git_options)
      next if !remote.success? || !remote.stdout.start_with?("https://", "http://")

      helpers = system_command("git", args: ["config", "--get-urlmatch", "credential.helper", remote.stdout.chomp],
                                      **git_options)
      env["GH_TOKEN"] = token if helpers.success? && helpers.stdout.lines.last&.strip.present?
    end
  end

  # Local, read-only repository inspections (`git --git-dir … rev-parse`/`show`)
  # can run while staging inside the sandbox, where reading the user's global Git
  # config is denied and makes Git exit. Null it here, unlike the download-time
  # commands that read it for credential helpers.
  sig { returns(T::Hash[String, String]) }
  def local_git_env
    require "utils/git"
    env.except("GH_TOKEN").merge(Utils::Git.no_global_config_env)
  end

  sig { override.returns(String) }
  def cache_tag
    if partial_clone_sparse_checkout?
      "git-sparse"
    else
      "git"
    end
  end

  sig { returns(Integer) }
  def cache_version
    0
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    config_repo
    update_repo(timeout:)
    checkout(timeout:)
    reset
    update_submodules(timeout:) if submodules?
  end

  sig { returns(T::Boolean) }
  def shallow_dir?
    (git_dir/"shallow").exist?
  end

  sig { returns(Pathname) }
  def git_dir
    cached_location/".git"
  end

  sig { override.returns(String) }
  def current_revision
    system_command("git", args: ["--git-dir", git_dir, "rev-parse", "-q", "--verify", "HEAD"],
                          env: local_git_env, print_stderr: false).stdout.strip
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    silent_command("git", args: ["-C", cached_location, "status", "-s"]).success?
  end

  sig { returns(T::Boolean) }
  def submodules?
    (cached_location/".gitmodules").exist?
  end

  sig { returns(T::Boolean) }
  def partial_clone_sparse_checkout?
    return false if @only_path.blank?

    require "utils/git"
    Utils::Git.supports_partial_clone_sparse_checkout?
  end

  sig { returns(String) }
  def refspec
    case @ref_type
    when :branch then "+refs/heads/#{@ref}:refs/remotes/origin/#{@ref}"
    when :tag    then "+refs/tags/#{@ref}:refs/tags/#{@ref}"
    else              default_refspec
    end
  end

  sig { returns(String) }
  def default_refspec
    # https://git-scm.com/book/en/v2/Git-Internals-The-Refspec
    "+refs/heads/*:refs/remotes/origin/*"
  end

  sig { void }
  def config_repo
    command! "git",
             args:  ["config", "remote.origin.url", @url],
             chdir: cached_location
    command! "git",
             args:  ["config", "remote.origin.fetch", refspec],
             chdir: cached_location
    command! "git",
             args:  ["config", "remote.origin.tagOpt", "--no-tags"],
             chdir: cached_location
    command! "git",
             args:  ["config", "advice.detachedHead", "false"],
             chdir: cached_location
    command! "git",
             args:  ["config", "core.fsmonitor", "false"],
             chdir: cached_location

    return unless partial_clone_sparse_checkout?

    command! "git",
             args:  ["config", "origin.partialclonefilter", "blob:none"],
             chdir: cached_location
    configure_sparse_checkout
  end

  sig { params(timeout: T.nilable(Time)).void }
  def update_repo(timeout: nil)
    return if @ref_type != :branch && ref?

    # Convert any shallow clone to full clone
    if shallow_dir?
      command! "git",
               args:    ["fetch", "origin", "--unshallow"],
               chdir:   cached_location,
               timeout: Utils::Timer.remaining(timeout)
    else
      command! "git",
               args:    ["fetch", "origin"],
               chdir:   cached_location,
               timeout: Utils::Timer.remaining(timeout)
    end
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    command! "git",
             args:    clone_args,
             timeout: Utils::Timer.remaining(timeout)

    command! "git",
             args:    ["config", "homebrew.cacheversion", cache_version],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)

    configure_sparse_checkout if partial_clone_sparse_checkout?

    checkout(timeout:)
    update_submodules(timeout:) if submodules?
  end

  sig { params(timeout: T.nilable(Time)).void }
  def checkout(timeout: nil)
    ohai "Checking out #{@ref_type} #{@ref}" if @ref
    command! "git", args: ["checkout", "-f", @ref, "--"], chdir: cached_location,
                    timeout: Utils::Timer.remaining(timeout)
  end

  sig { void }
  def reset
    ref = case @ref_type
    when :branch
      "origin/#{@ref}"
    when :revision, :tag
      @ref
    end

    command! "git",
             args:  ["reset", "--hard", *ref, "--"],
             chdir: cached_location
  end

  sig { params(timeout: T.nilable(Time)).void }
  def update_submodules(timeout: nil)
    command! "git",
             args:    ["submodule", "foreach", "--recursive", "git submodule sync"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
    command! "git",
             args:    ["submodule", "update", "--init", "--recursive"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
    fix_absolute_submodule_gitdir_references!
  end

  # When checking out Git repositories with recursive submodules, some Git
  # versions create `.git` files with absolute instead of relative `gitdir:`
  # pointers. This works for the cached location, but breaks various Git
  # operations once the affected Git resource is staged, i.e. recursively
  # copied to a new location. (This bug was introduced in Git 2.7.0 and fixed
  # in 2.8.3. Clones created with affected version remain broken.)
  # See https://github.com/Homebrew/homebrew-core/pull/1520 for an example.
  sig { void }
  def fix_absolute_submodule_gitdir_references!
    submodule_dirs = command!("git",
                              args:  ["submodule", "--quiet", "foreach", "--recursive", "pwd"],
                              chdir: cached_location).stdout

    submodule_dirs.lines.map(&:chomp).each do |submodule_dir|
      work_dir = Pathname.new(submodule_dir)

      # Only check and fix if `.git` is a regular file, not a directory.
      dot_git = work_dir/".git"
      next unless dot_git.file?

      # This Ruby write runs in the parent, outside Git's sandbox.
      Utils::Path.ensure_child_of!(cached_location, dot_git,
                                   message: "Git submodule metadata escapes the download directory: #{dot_git}")

      git_dir = dot_git.read.chomp[/^gitdir: (.*)$/, 1]
      if git_dir.nil?
        onoe "Failed to parse '#{dot_git}'." if Homebrew::EnvConfig.developer?
        next
      end

      # Only attempt to fix absolute paths.
      next unless git_dir.start_with?("/")

      # Make the `gitdir:` reference relative to the working directory.
      relative_git_dir = Pathname.new(git_dir).relative_path_from(work_dir)
      dot_git.atomic_write("gitdir: #{relative_git_dir}\n")
    end
  end

  sig { void }
  def configure_sparse_checkout
    command! "git",
             args:  ["config", "core.sparseCheckout", "true"],
             chdir: cached_location
    command! "git",
             args:  ["config", "core.sparseCheckoutCone", "true"],
             chdir: cached_location

    (git_dir/"info").mkpath
    (git_dir/"info/sparse-checkout").atomic_write("#{@only_path}\n")
  end
end
