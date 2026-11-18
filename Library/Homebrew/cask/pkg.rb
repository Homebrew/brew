# typed: strict
# frozen_string_literal: true

require "cask/macos"
require "utils/output"

module Cask
  # Helper class for uninstalling `.pkg` installers.
  class Pkg
    include ::Utils::Output::Mixin

    sig { params(regexp: String, command: T.class_of(SystemCommand)).returns(T::Array[Pkg]) }
    def self.all_matching(regexp, command)
      command.run("/usr/sbin/pkgutil", args: ["--pkgs=#{regexp}"]).stdout.split("\n").map do |package_id|
        new(package_id.chomp, command)
      end
    end

    sig { returns(String) }
    attr_reader :package_id

    sig { params(package_id: String, command: T.class_of(SystemCommand)).void }
    def initialize(package_id, command = SystemCommand)
      @pkgutil_bom_files = T.let(nil, T.nilable(T::Array[Pathname]))
      @pkgutil_bom_specials = T.let(nil, T.nilable(T::Array[Pathname]))
      @pkgutil_bom_dirs = T.let(nil, T.nilable(T::Array[Pathname]))
      @pkgutil_bom_all = T.let(nil, T.nilable(T::Array[Pathname]))
      @root = T.let(nil, T.nilable(Pathname))

      @package_id = package_id
      @command = command
    end

    sig { void }
    def uninstall
      unless pkgutil_bom_files.empty?
        odebug "Deleting pkg files"
        @command.run!(
          "/usr/bin/xargs",
          args:         ["-0", "--", "/bin/rm", "--"],
          input:        pkgutil_bom_files.join("\0"),
          sudo:         true,
          sudo_as_root: true,
        )
      end

      unless pkgutil_bom_specials.empty?
        odebug "Deleting pkg symlinks and special files"
        @command.run!(
          "/usr/bin/xargs",
          args:         ["-0", "--", "/bin/rm", "--"],
          input:        pkgutil_bom_specials.join("\0"),
          sudo:         true,
          sudo_as_root: true,
        )
      end

      unless pkgutil_bom_dirs.empty?
        odebug "Deleting pkg directories"
        rmdir(pkgutil_bom_dirs.sort_by { |path| -path.to_s.split(File::SEPARATOR).count })
      end

      rmdir(root) unless OS::Mac.undeletable?(root)

      forget
    end

    sig { void }
    def forget
      odebug "Unregistering pkg receipt (aka forgetting)"
      @command.run!(
        "/usr/sbin/pkgutil",
        args:         ["--forget", package_id],
        sudo:         true,
        sudo_as_root: true,
      )
    end

    sig { returns(T::Array[Pathname]) }
    def pkgutil_bom_files
      @pkgutil_bom_files ||= pkgutil_bom_all.select(&:file?) - pkgutil_bom_specials
    end

    sig { returns(T::Array[Pathname]) }
    def pkgutil_bom_specials
      @pkgutil_bom_specials ||= pkgutil_bom_all.select { it.symlink? || it.chardev? || it.blockdev? }
    end

    sig { returns(T::Array[Pathname]) }
    def pkgutil_bom_dirs
      @pkgutil_bom_dirs ||= pkgutil_bom_all.select(&:directory?) - pkgutil_bom_specials
    end

    sig { returns(T::Array[Pathname]) }
    def pkgutil_bom_all
      @pkgutil_bom_all ||= @command.run!("/usr/sbin/pkgutil", args: ["--files", package_id])
                                   .stdout
                                   .split("\n")
                                   .map { |path| root.join(path) }
                                   .reject { |path| OS::Mac.undeletable?(path) }
    end

    sig { returns(Pathname) }
    def root
      @root ||= Pathname.new(info.fetch("volume")).join(info.fetch("install-location"))
    end

    sig { returns(T.untyped) }
    def info
      return @info if @info

      resolved_info = @command.run!("/usr/sbin/pkgutil", args: ["--pkg-info-plist", package_id]).plist
      @info = T.let(resolved_info, T.untyped)
    end

    private

    # Helper script to delete empty directories after deleting `.DS_Store` files and broken symlinks.
    # Needed in order to execute all file operations with `sudo`.
    RMDIR_SH = T.let((HOMEBREW_LIBRARY_PATH/"cask/utils/rmdir.sh").freeze, Pathname)
    private_constant :RMDIR_SH

    sig { params(path: T.any(Pathname, T::Array[Pathname])).void }
    def rmdir(path)
      @command.run!(
        "/usr/bin/xargs",
        args:         ["-0", "--", RMDIR_SH.to_s],
        input:        Array(path).join("\0"),
        sudo:         true,
        sudo_as_root: true,
      )
    end
  end
end
