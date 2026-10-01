# typed: strict
# frozen_string_literal: true

require "on_system"
require "utils/user"
require "open3"
require "utils/output"

module Cask
  # Helper functions for various cask operations.
  module Utils
    extend ::Utils::Output::Mixin

    BUG_REPORTS_URL = "https://github.com/Homebrew/homebrew-cask#reporting-bugs"
    FULL_DISK_ACCESS_TCC_PATH = "~/Library/Application Support/com.apple.TCC"

    sig { params(access: String).returns(String) }
    def self.privacy_security_preference_pane(access)
      navigation_path = if OnSystem.os_condition_met?(:monterey, :or_older)
        "System Preferences → Security & Privacy → Privacy"
      else
        "System Settings → Privacy & Security"
      end

      "#{navigation_path} → #{access}"
    end

    sig { returns(T::Boolean) }
    def self.full_disk_access_enabled?
      File.readable?(File.expand_path(FULL_DISK_ACCESS_TCC_PATH))
    end

    sig { params(path: Pathname, command: T.class_of(SystemCommand)).void }
    def self.gain_permissions_mkpath(path, command: SystemCommand)
      dir = path.ascend.find(&:directory?)
      return if path == dir

      if dir&.writable?
        path.mkpath
      else
        command.run!("mkdir", args: ["-p", "--", path], sudo: nil, print_stderr: false)
      end
    end

    sig { params(path: Pathname, command: T.class_of(SystemCommand)).void }
    def self.gain_permissions_rmdir(path, command: SystemCommand)
      # `-h` unconditionally: it is a no-op on a real directory and avoids
      # deciding from a path that could be replaced before the recovery runs.
      gain_permissions(path, ["-h"], command) do |p|
        if p.parent.writable?
          FileUtils.rmdir p
        else
          command.run!("rmdir", args: ["--", p], sudo: nil, print_stderr: false)
        end
      end
    end

    sig { params(path: Pathname, command: T.class_of(SystemCommand)).void }
    def self.gain_permissions_remove(path, command: SystemCommand)
      directory = false
      permission_flags = if path.symlink?
        ["-h"]
      elsif path.directory?
        directory = true
        ["-R"]
      elsif path.exist?
        []
      else
        # Nothing to remove.
        return
      end

      gain_permissions(path, permission_flags, command) do |p|
        if p.parent.writable?
          if directory
            FileUtils.rm_r p
          else
            FileUtils.rm_f p
          end
        else
          recursive_flag = directory ? ["-R"] : []
          command.run!("/bin/rm", args: recursive_flag + ["-f", "--", p], sudo: nil, print_stderr: false)
        end
      end
    end

    sig {
      params(
        path:         Pathname,
        command_args: T::Array[String],
        command:      T.class_of(SystemCommand),
        _block:       T.proc.params(path: Pathname).void,
      ).void
    }
    def self.gain_permissions(path, command_args, command, &_block)
      tried_permissions = T.let(false, T::Boolean)
      tried_ownership = T.let(false, T::Boolean)
      begin
        yield path
      rescue
        target = path.cleanpath
        flags = target.symlink? ? ["-h"] : command_args

        # in case of permissions problems
        unless tried_permissions
          print_stderr = Context.current.debug? || Context.current.verbose?
          command.run("/usr/bin/chflags",
                      print_stderr:,
                      args:         flags + ["--", "000", target])
          command.run("chmod",
                      print_stderr:,
                      args:         flags + ["--", "u+rwx", target])
          command.run("chmod",
                      print_stderr:,
                      args:         flags + ["-N", target])
          tried_permissions = true
          retry # rmtree
        end

        # in case of ownership problems
        recursive = flags.include?("-R")
        if !tried_ownership && ownership_problem?(target, recursive:)
          ohai "Using sudo to gain ownership of path '#{path}'"
          command.run("chown",
                      args: flags + ["--", User.current.to_s, target],
                      sudo: true)
          tried_ownership = true
          # retry chflags/chmod after chown
          tried_permissions = false
          retry # rmtree
        end

        raise
      end
    end

    # Whether `sudo chown` could plausibly fix the failure we just rescued: the
    # `chflags`/`chmod` above run without `sudo`, so they only fail on paths we
    # do not own. `lstat` rather than `owned?`, which would follow a symlink.
    sig { params(path: Pathname, recursive: T::Boolean).returns(T::Boolean) }
    def self.ownership_problem?(path, recursive:)
      return false if Process.euid.zero?

      paths = recursive ? path.find : [path]
      paths.any? do |candidate|
        candidate.lstat.uid != Process.euid
      rescue SystemCallError
        false
      end
    rescue SystemCallError
      false
    end

    sig { params(path: Pathname).returns(T::Boolean) }
    def self.path_occupied?(path)
      path.exist? || path.symlink?
    end

    sig { params(name: String).returns(String) }
    def self.token_from(name)
      name.downcase
          .gsub("+", "-plus-")
          .gsub(/[ _·•]/, "-")
          .gsub(/[^\w@-]/, "")
          .gsub(/--+/, "-")
          .delete_prefix("-")
          .delete_suffix("-")
    end
  end
end
