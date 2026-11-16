# typed: strict
# frozen_string_literal: true

require "tempfile"
require "cask/macos"
require "system_command"
require "utils/output"

module UnpackStrategy
  # Strategy for unpacking disk images.
  class Dmg
    extend SystemCommand::Mixin
    include UnpackStrategy

    # Helper module for listing the contents of a volume mounted from a disk image.
    module Bom
      extend Utils::Output::Mixin
      extend SystemCommand::Mixin

      DMG_METADATA = T.let(Set.new([
        ".background",
        ".com.apple.timemachine.donotpresent",
        ".com.apple.timemachine.supported",
        ".DocumentRevisions-V100",
        ".DS_Store",
        ".fseventsd",
        ".MobileBackups",
        ".Spotlight-V100",
        ".TemporaryItems",
        ".Trashes",
        ".VolumeIcon.icns",
        ".HFS+ Private Directory Data\r", # do not remove `\r`, it is a part of directory name
        ".HFS+ Private Data\r",
        "Desktop DB",
        "Desktop DF",
      ]).freeze, T::Set[String])
      private_constant :DMG_METADATA

      class Error < RuntimeError; end

      class EmptyError < Error
        sig { params(path: Pathname).void }
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

      sig { params(verbose: T::Boolean).void }
      def eject(verbose: false)
        tries = 3
        begin
          return unless path.exist?

          if tries > 1
            disk_info = system_command!(
              "diskutil",
              args:         ["info", "-plist", path],
              print_stderr: false,
              verbose:,
            )

            # For HFS, just use <mount-path>
            # For APFS, find the <physical-store> corresponding to <mount-path>
            eject_paths = disk_info.plist
                                   .fetch("APFSPhysicalStores", [])
                                   .filter_map { |store| store["APFSPhysicalStore"] }
                                   .presence || [path]

            eject_paths.each do |eject_path|
              system_command! "diskutil",
                              args:         ["eject", eject_path],
                              print_stderr: false,
                              verbose:
            end
          else
            system_command! "diskutil",
                            args:         ["unmount", "force", path],
                            print_stderr: false,
                            verbose:
          end
        rescue ErrorDuringExecution => e
          raise e if (tries -= 1).zero?

          sleep 1
          retry
        end
      end

      sig { override.returns(T::Array[String]) }
      def self.extensions = []

      sig { override.params(_path: Path).returns(T::Boolean) }
      def self.can_extract?(_path) = false

      private

      sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
      def extract_to_dir(unpack_dir, basename:, verbose:)
        tries = 3
        bom = begin
          Bom.bom(path)
        rescue Bom::EmptyError => e
          raise e if (tries -= 1).zero?

          sleep 1
          retry
        end

        Tempfile.create(["", ".bom"]) do |bomfile|
          bomfile.close

          Tempfile.create(["", ".list"]) do |filelist|
            filelist.puts(bom)
            filelist.close

            system_command! "mkbom",
                            args:    ["-s", "-i", filelist.path, "--", bomfile.path],
                            verbose:
          end

          system_command!("ditto",
                          args:    ["--bom", bomfile.path, "--", path, unpack_dir],
                          verbose:)

          FileUtils.chmod "u+w", Pathname.glob(unpack_dir/"**/*", File::FNM_DOTMATCH).reject(&:symlink?)
        end
      end
    end

    # UDIF disk images end in a 512-byte "koly" trailer. Its 8-byte big-endian fields at byte 216
    # hold the offset and length of an XML plist of resources, where a license agreement is `LPic`.
    UDIF_TRAILER_SIZE = 512
    private_constant :UDIF_TRAILER_SIZE
    UDIF_XML_FIELDS_OFFSET = 216
    private_constant :UDIF_XML_FIELDS_OFFSET

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".dmg"]
    end

    sig { override.params(path: Path).returns(T::Boolean) }
    def self.can_extract?(path)
      stdout, _, status = system_command("hdiutil", args: ["imageinfo", "-format", path], print_stderr: false).to_a
      (status.success? && !stdout.empty?) || false
    end

    sig { returns(T::Boolean) }
    def self.diskutil_image? = false

    sig { params(verbose: T::Boolean, _block: T.proc.params(arg0: T::Array[Mount]).void).void }
    def mount(verbose: false, &_block)
      Dir.mktmpdir("homebrew-dmg", HOMEBREW_TEMP) do |mount_dir|
        mount_dir = Pathname(mount_dir)

        plist = attach_with_diskutil(mount_dir, verbose:) if self.class.diskutil_image?
        plist ||= attach_with_hdiutil(mount_dir, verbose:)

        mounts = if plist.respond_to?(:fetch)
          plist.fetch("system-entities", [])
               .filter_map { |entity| entity["mount-point"] }
               .map { |path| Mount.new(path) }
        else
          []
        end

        begin
          yield mounts
        ensure
          mounts.each do |mount|
            mount.eject(verbose:)
          end
        end
      end
    end

    private

    # Strips a license agreement before attaching, as `attach_with_hdiutil` does, so it is never
    # agreed to. If one is missed, attaching with nothing on standard input cancels, and `PAGER`
    # stops `diskutil` paging the agreement on a terminal. Returns `nil` when `diskutil` fails (e.g.
    # on a multi-volume image, which `--mountPoint` doesn't support) so `hdiutil` can mount it.
    sig { params(mount_dir: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def attach_with_diskutil(mount_dir, verbose:)
      image_path = path
      if license_agreement?
        # A RAW image has no UDIF resources, so converting to one drops the license agreement
        # like `hdiutil convert -format UDTO` does.
        image_path = mount_dir/path.basename.sub_ext(".img")
        converted = system_command(
          "diskutil",
          args:         ["image", "create", "from", "--format", "RAW", path, image_path],
          env:          { "PAGER" => "true" },
          print_stderr: false,
          verbose:,
        )
        unless converted.success?
          odebug "`diskutil image create from` failed for '#{path}', retrying with `hdiutil`.", converted.stderr
          return
        end
      end

      mount_point = mount_dir/"mount"
      mount_point.mkpath

      result = system_command(
        "diskutil",
        args:         [
          "image", "attach", "--plist", "--readOnly", "--nobrowse",
          "--mountPoint", mount_point, image_path
        ],
        env:          { "PAGER" => "true" },
        print_stderr: false,
        verbose:,
      )
      return result.plist if result.success?

      odebug "`diskutil image attach` failed for '#{path}', retrying with `hdiutil`.", result.stderr
      # `hdiutil` converts the original again, so don't keep two uncompressed copies.
      image_path.unlink if image_path != path
      nil
    end

    sig { returns(T::Boolean) }
    def license_agreement?
      size = path.size
      return false if size < UDIF_TRAILER_SIZE

      trailer = path.binread(UDIF_TRAILER_SIZE, size - UDIF_TRAILER_SIZE)
      return false if trailer.nil? || !trailer.start_with?("koly")

      xml_offset, xml_length = trailer.unpack("@#{UDIF_XML_FIELDS_OFFSET}Q>Q>")
      return false if !xml_offset.is_a?(Integer) || !xml_length.is_a?(Integer)
      return false if xml_length.zero? || xml_offset + xml_length > size

      # Match the key rather than parse XML straight from the image.
      path.binread(xml_length, xml_offset).to_s.include?("<key>LPic</key>")
    end

    sig { params(mount_dir: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def attach_with_hdiutil(mount_dir, verbose:)
      without_eula = system_command(
        "hdiutil",
        args:         [
          "attach", "-plist", "-nobrowse", "-readonly",
          "-mountrandom", mount_dir, path
        ],
        input:        "qn\n",
        print_stderr: false,
        verbose:,
      )

      # If mounting without agreeing to EULA succeeded, there is none.
      return without_eula.plist if without_eula.success?

      without_eula.assert_success! if without_eula.stdout.empty?

      cdr_path = mount_dir/path.basename.sub_ext(".cdr")

      quiet_flag = "-quiet" unless verbose

      system_command!(
        "hdiutil",
        args:    [
          "convert", *quiet_flag, "-format", "UDTO", "-o", cdr_path, path
        ],
        verbose:,
      )

      with_eula = system_command!(
        "hdiutil",
        args:    [
          "attach", "-plist", "-nobrowse", "-readonly",
          "-mountrandom", mount_dir, cdr_path
        ],
        verbose:,
      )

      if verbose && !(eula_text = without_eula.stdout).empty?
        ohai "Software License Agreement for '#{path}':", eula_text
      end

      with_eula.plist
    end

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      mount(verbose:) do |mounts|
        raise "No mounts found in '#{path}'; perhaps this is a bad disk image?" if mounts.empty?

        mounts.each do |mount|
          mount.extract(to: unpack_dir, verbose:)
        end
      end
    end
  end
end

require "extend/os/unpack_strategy/dmg"
