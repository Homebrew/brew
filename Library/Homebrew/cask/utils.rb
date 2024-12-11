# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/user"
require "open3"

module Cask
  # Helper functions for various cask operations.
  module Utils
    BUG_REPORTS_URL = "https://github.com/Homebrew/homebrew-cask#reporting-bugs"

    def self.gain_permissions_mkpath(path, command: SystemCommand)
      dir = path.ascend.find(&:directory?)
      return if path == dir

      if dir.writable?
        path.mkpath
      else
        command.run!("/bin/mkdir", args: ["-p", "--", path], sudo: true, print_stderr: false)
      end
    end

    def self.gain_permissions_rmdir(path, command: SystemCommand)
      gain_permissions(path, [], command) do |p|
        if p.parent.writable?
          FileUtils.rmdir p
        else
          command.run!("/bin/rmdir", args: ["--", p], sudo: true, print_stderr: false)
        end
      end
    end

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
          command.run!("/bin/rm", args: recursive_flag + ["-f", "--", p], sudo: true, print_stderr: false)
        end
      end
    end

    def self.gain_permissions(path, command_args, command)
      tried_permissions = false
      tried_ownership = false
      begin
        yield path
      rescue
        # in case of permissions problems
        unless tried_permissions
          print_stderr = Context.current.debug? || Context.current.verbose?
          # TODO: Better handling for the case where path is a symlink.
          #       The `-h` and `-R` flags cannot be combined and behavior is
          #       dependent on whether the file argument has a trailing
          #       slash. This should do the right thing, but is fragile.
          command.run("/usr/bin/chflags",
                      print_stderr:,
                      args:         command_args + ["--", "000", path])
          command.run("/bin/chmod",
                      print_stderr:,
                      args:         command_args + ["--", "u+rwx", path])
          command.run("/bin/chmod",
                      print_stderr:,
                      args:         command_args + ["-N", path])
          tried_permissions = true
          retry # rmtree
        end

        unless tried_ownership
          # in case of ownership problems
          # TODO: Further examine files to see if ownership is the problem
          #       before using `sudo` and `chown`.
          ohai "Using sudo to gain ownership of path '#{path}'"
          command.run("/usr/sbin/chown",
                      args: command_args + ["--", User.current, path],
                      sudo: true)
          tried_ownership = true
          # retry chflags/chmod after chown
          tried_permissions = false
          retry # rmtree
        end

        raise
      end
    end

    sig { params(path: Pathname).returns(T::Boolean) }
    def self.path_occupied?(path)
      path.exist? || path.symlink?
    end

    sig { params(name: String).returns(String) }
    def self.token_from(name)
      name.downcase
          .gsub("+", "-plus-")
          .gsub("@", "-at-")
          .gsub(/[ _·•]/, "-")
          .gsub(/[^\w-]/, "")
          .gsub(/--+/, "-")
          .delete_prefix("-")
          .delete_suffix("-")
    end

    sig { returns(String) }
    def self.error_message_with_suggestions
      <<~EOS
        Follow the instructions here:
          #{Formatter.url(BUG_REPORTS_URL)}
      EOS
    end

    def self.method_missing_message(method, token, section = nil)
      message = "Unexpected method '#{method}' called "
      message << "during #{section} " if section
      message << "on Cask #{token}."

      ofail "#{message}\n#{error_message_with_suggestions}"
    end
  end
end
