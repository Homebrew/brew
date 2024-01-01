# typed: true
# frozen_string_literal: true

require "tempfile"

module UnpackStrategy
  # Strategy for unpacking disk images.
  class Dmg
    include UnpackStrategy

    # Helper module for listing the contents of a volume mounted from a disk image.
    module Bom
      DMG_METADATA = Set.new(%w[
        .background
        .com.apple.timemachine.donotpresent
        .com.apple.timemachine.supported
        .DocumentRevisions-V100
        .DS_Store
        .fseventsd
        .MobileBackups
        .Spotlight-V100
        .TemporaryItems
        .Trashes
        .VolumeIcon.icns
      ]).freeze
      private_constant :DMG_METADATA

      class Error < RuntimeError; end

      class EmptyError < Error
        def initialize(path)
          super "BOM for path '#{path}' is empty."
        end
      end

      # Check if path is considered disk image metadata.
      sig { params(pathname: Pathname).returns(T::Boolean) }
      def self.dmg_metadata?(pathname)
        DMG_METADATA.include?(pathname.cleanpath.ascend.to_a.last.to_s)
      end

      # Check if path is a symlink to a system directory (commonly to /Applications).
      sig { params(pathname: Pathname).returns(T::Boolean) }
      def self.system_dir_symlink?(pathname)
        pathname.symlink? && MacOS.system_dir?(pathname.dirname.join(pathname.readlink))
      end

      sig { params(pathname: Pathname).returns(String) }
      def self.bom(pathname)
        tries = 0
        result = loop do
          # We need to use `find` here instead of Ruby in order to properly handle
          # file names containing special characters, such as “e” + “´” vs. “é”.
          r = system_command("find", args: [".", "-print0"], chdir: pathname, print_stderr: false)
          tries += 1

          # Spurious bug on CI, which in most cases can be worked around by retrying.
          break r unless r.stderr.match?(/Interrupted system call/i)

          raise "Command `#{r.command.shelljoin}` was interrupted." if tries >= 3
        end

        odebug "Command `#{result.command.shelljoin}` in '#{pathname}' took #{tries} tries." if tries > 1

        bom_paths = result.stdout.split("\0")

        raise EmptyError, pathname if bom_paths.empty?

        bom_paths
          .reject { |path| dmg_metadata?(Pathname(path)) }
          .reject { |path| system_dir_symlink?(pathname/path) }
          .join("\n")
      end
    end

    # Strategy for unpacking a volume mounted from a disk image.
    class Mount
      include UnpackStrategy

      def eject(verbose: false)
        tries = 3
        begin
          return unless path.exist?

          if tries > 1
            disk_info = system_command!(
              "diskutil",
              args:         ["info", "-plist", path],
              print_stderr: false,
              verbose:      verbose,
            )

            # For HFS, just use <mount-path>
            # For APFS, find the <physical-store> corresponding to <mount-path>
            eject_paths = disk_info.plist
                                   .fetch("APFSPhysicalStores", [])
                                   .map { |store| store["APFSPhysicalStore"] }
                                   .compact
                                   .presence || [path]

            eject_paths.each do |eject_path|
              system_command! "diskutil",
                              args:         ["eject", eject_path],
                              print_stderr: false,
                              verbose:      verbose
            end
          else
            system_command! "diskutil",
                            args:         ["unmount", "force", path],
                            print_stderr: false,
                            verbose:      verbose
          end
        rescue ErrorDuringExecution => e
          raise e if (tries -= 1).zero?

          sleep 1
          retry
        end
      end

      private

      sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
      def extract_to_dir(unpack_dir, basename:, verbose:)
        tries = 3
        bom = begin
          Bom.bom(path)
        rescue Bom::EmptyError => e
          raise e if (tries -= 1).zero?

          sleep 1
          retry
        end

        Tempfile.open(["", ".bom"]) do |bomfile|
          bomfile.close

          Tempfile.open(["", ".list"]) do |filelist|
            filelist.puts(bom)
            filelist.close

            system_command! "mkbom",
                            args:    ["-s", "-i", filelist.path, "--", bomfile.path],
                            verbose: verbose
          end

          system_command! "ditto",
                          args:    ["--bom", bomfile.path, "--", path, unpack_dir],
                          verbose: verbose

          FileUtils.chmod "u+w", Pathname.glob(unpack_dir/"**/*", File::FNM_DOTMATCH).reject(&:symlink?)
        end
      end
    end
    private_constant :Mount

    sig { returns(T::Array[String]) }
    def self.extensions
      [".dmg"]
    end

    def self.can_extract?(path)
      stdout, _, status = system_command("hdiutil", args: ["imageinfo", "-format", path], print_stderr: false)
      status.success? && !stdout.empty?
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      mount(verbose: verbose) do |mounts|
        raise "No mounts found in '#{path}'; perhaps this is a bad disk image?" if mounts.empty?

        mounts.each do |mount|
          mount.extract(to: unpack_dir, verbose: verbose)
        end
      end
    end

    def mount(verbose: false)
      Dir.mktmpdir do |mount_dir|
        mount_dir = Pathname(mount_dir)

        without_eula = system_command(
          "hdiutil",
          args:         [
            "attach", "-plist", "-nobrowse", "-readonly",
            "-mountrandom", mount_dir, path
          ],
          input:        "qn\n",
          print_stderr: false,
          verbose:      verbose,
        )

        # If mounting without agreeing to EULA succeeded, there is none.
        plist = if without_eula.success?
          without_eula.plist
        else
          cdr_path = mount_dir/path.basename.sub_ext(".cdr")

          quiet_flag = "-quiet" unless verbose

          system_command!(
            "hdiutil",
            args:    [
              "convert", *quiet_flag, "-format", "UDTO", "-o", cdr_path, path
            ],
            verbose: verbose,
          )

          with_eula = system_command!(
            "hdiutil",
            args:    [
              "attach", "-plist", "-nobrowse", "-readonly",
              "-mountrandom", mount_dir, cdr_path
            ],
            verbose: verbose,
          )

          if verbose && !(eula_text = without_eula.stdout).empty?
            ohai "Software License Agreement for '#{path}':", eula_text
          end

          with_eula.plist
        end

        mounts = if plist.respond_to?(:fetch)
          plist.fetch("system-entities", [])
               .map { |entity| entity["mount-point"] }
               .compact
               .map { |path| Mount.new(path) }
        else
          []
        end

        begin
          yield mounts
        ensure
          mounts.each do |mount|
            mount.eject(verbose: verbose)
          end
        end
      end
    end
  end
end
