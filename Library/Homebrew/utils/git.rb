# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "system_command"

module Utils
  # Helper functions for querying Git information.
  #
  # @see GitRepository
  module Git
    extend SystemCommand::Mixin

    def self.available?
      version.present?
    end

    def self.version
      return @version if defined?(@version)

      stdout, _, status = system_command(git, args: ["--version"], verbose: false, print_stderr: false)
      @version = status.success? ? stdout.chomp[/git version (\d+(?:\.\d+)*)/, 1] : nil
    end

    def self.path
      return unless available?
      return @path if defined?(@path)

      @path = Utils.popen_read(git, "--homebrew=print-path").chomp.presence
    end

    def self.git
      return @git if defined?(@git)

      @git = HOMEBREW_SHIMS_PATH/"shared/git"
    end

    def self.remote_exists?(url)
      return true unless available?

      quiet_system "git", "ls-remote", url
    end

    def self.clear_available_cache
      remove_instance_variable(:@version) if defined?(@version)
      remove_instance_variable(:@path) if defined?(@path)
      remove_instance_variable(:@git) if defined?(@git)
    end

    def self.last_revision_commit_of_file(repo, file, before_commit: nil)
      args = if before_commit.nil?
        ["--skip=1"]
      else
        [before_commit.split("..").first]
      end

      Utils.popen_read(git, "-C", repo, "log", "--format=%h", "--abbrev=7", "--max-count=1", *args, "--", file).chomp
    end

    def self.last_revision_commit_of_files(repo, files, before_commit: nil)
      args = if before_commit.nil?
        ["--skip=1"]
      else
        [before_commit.split("..").first]
      end

      # git log output format:
      #   <commit_hash>
      #   <file_path1>
      #   <file_path2>
      #   ...
      # return [<commit_hash>, [file_path1, file_path2, ...]]
      rev, *paths = Utils.popen_read(
        git, "-C", repo, "log",
        "--pretty=format:%h", "--abbrev=7", "--max-count=1",
        "--diff-filter=d", "--name-only", *args, "--", *files
      ).lines.map(&:chomp).reject(&:empty?)
      [rev, paths]
    end

    sig {
      params(repo: T.any(Pathname, String), file: T.any(Pathname, String), before_commit: T.nilable(String))
        .returns(String)
    }
    def self.last_revision_of_file(repo, file, before_commit: nil)
      relative_file = Pathname(file).relative_path_from(repo)
      commit_hash = last_revision_commit_of_file(repo, relative_file, before_commit:)
      file_at_commit(repo, file, commit_hash)
    end

    def self.file_at_commit(repo, file, commit)
      relative_file = Pathname(file)
      relative_file = relative_file.relative_path_from(repo) if relative_file.absolute?
      Utils.popen_read(git, "-C", repo, "show", "#{commit}:#{relative_file}")
    end

    def self.ensure_installed!
      return if available?

      # we cannot install brewed git if homebrew/core is unavailable.
      if CoreTap.instance.installed?
        begin
          # Otherwise `git` will be installed from source in tests that need it. This is slow
          # and will also likely fail due to `OS::Linux` and `OS::Mac` being undefined.
          raise "Refusing to install Git on a generic OS." if ENV["HOMEBREW_TEST_GENERIC_OS"]

          ensure_formula_installed!("git")
          clear_available_cache
        rescue
          raise "Git is unavailable"
        end
      end

      raise "Git is unavailable" unless available?
    end

    def self.set_name_email!(author: true, committer: true)
      if Homebrew::EnvConfig.git_name
        ENV["GIT_AUTHOR_NAME"] = Homebrew::EnvConfig.git_name if author
        ENV["GIT_COMMITTER_NAME"] = Homebrew::EnvConfig.git_name if committer
      end

      if Homebrew::EnvConfig.git_committer_name && committer
        ENV["GIT_COMMITTER_NAME"] = Homebrew::EnvConfig.git_committer_name
      end

      if Homebrew::EnvConfig.git_email
        ENV["GIT_AUTHOR_EMAIL"] = Homebrew::EnvConfig.git_email if author
        ENV["GIT_COMMITTER_EMAIL"] = Homebrew::EnvConfig.git_email if committer
      end

      return unless committer
      return unless Homebrew::EnvConfig.git_committer_email

      ENV["GIT_COMMITTER_EMAIL"] = Homebrew::EnvConfig.git_committer_email
    end

    def self.setup_gpg!
      gnupg_bin = HOMEBREW_PREFIX/"opt/gnupg/bin"
      return unless gnupg_bin.directory?

      ENV["PATH"] = PATH.new(ENV.fetch("PATH")).prepend(gnupg_bin).to_s
    end

    # Special case of `git cherry-pick` that permits non-verbose output and
    # optional resolution on merge conflict.
    def self.cherry_pick!(repo, *args, resolve: false, verbose: false)
      cmd = [git, "-C", repo, "cherry-pick"] + args
      output = Utils.popen_read(*cmd, err: :out)
      if $CHILD_STATUS.success?
        puts output if verbose
        output
      else
        system git, "-C", repo, "cherry-pick", "--abort" unless resolve
        raise ErrorDuringExecution.new(cmd, status: $CHILD_STATUS, output: [[:stdout, output]])
      end
    end

    def self.supports_partial_clone_sparse_checkout?
      # There is some support for partial clones prior to 2.20, but we avoid using it
      # due to performance issues
      Version.new(version) >= Version.new("2.20.0")
    end
  end
end
