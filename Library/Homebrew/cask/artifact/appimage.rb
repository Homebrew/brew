# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"
require "cask/desktop_file_parser"

module Cask
  module Artifact
    # Artifact corresponding to the `app_image` stanza.
    class AppImage < Moved
      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        Pathname.new("#{config.appimagedir}/#{target}")
      end

      sig {
        override.params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          successor:    T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        successor: nil, reinstall: false, command: SystemCommand)
        # Some apps self-integrate their entries, which can be prevented by setting this var.
        # Ref: https://github.com/AppImage/AppImageSpec/blob/master/draft.md#desktop-integration
        environment = { "DESKTOPINTEGRATION" => "1" }

        # Read the desktop entries from the staged AppImage
        # so a conflicting entry fails the install before anything is moved.
        make_executable(source, command:) if source.file?
        desktop_entries = Dir.mktmpdir("appimage-", HOMEBREW_TEMP) do |tmpdir|
          extract_root = Pathname(tmpdir)/"squashfs-root"
          extract_from_appimage("*.desktop", extract_root:, command:)
            .each_with_object({}) do |embedded_desktop_file, entries|
            # Filter out large non-text binaries named `*.desktop` (e.g. cask opencode-desktop)
            next if !embedded_desktop_file.file? || embedded_desktop_file.size > DESKTOP_ENTRY_MAX_BYTES

            desktop_file = DesktopFileParser.new(embedded_desktop_file.read)
            unless desktop_file.desktop_entry?
              odebug "Skipping '#{embedded_desktop_file.basename}' as it is not a desktop entry"
              next
            end

            begin
              desktop_file.replace_program(target.to_s, environment:)
            rescue ArgumentError
              odebug "Skipping '#{embedded_desktop_file.basename}' due to malformed `Exec`"
              next
            end

            # The AppImage spec puts the icon `Icon` names at the root of the image.
            # A path would point outside it, usually to the developer's machine.
            icon_name = desktop_file.get("Icon").to_s
            if icon_name.present? && icon_name.exclude?("/")
              embedded_icon = extract_from_appimage("#{icon_name}.*", extract_root:, command:).find do |path|
                path.file? && DESKTOP_ENTRY_ICON_EXTENSIONS.include?(path.extname)
              end
              icon_extension = embedded_icon&.extname
            end
            # Fall back to the spec's `.DirIcon`, the only icon in e.g. cask vscodium,
            # typed by its contents as it has no extension.
            embedded_icon ||= extract_from_appimage(".DirIcon", extract_root:, command:).find(&:file?)
            icon_extension ||= case embedded_icon&.binread(DESKTOP_ENTRY_ICON_HEADER_BYTES)
            when /\A\x89PNG/n then ".png"
            when /<svg/ then ".svg"
            when %r{\A/\* XPM \*/} then ".xpm"
            end
            if embedded_icon && icon_extension
              # Name it after the entry, as `Icon` may be a path.
              icon = cask.staged_path/"#{embedded_desktop_file.basename(".desktop")}#{icon_extension}"
              FileUtils.cp embedded_icon, icon
              desktop_file.update("Icon") { icon.to_s }
            end

            entries[embedded_desktop_file.basename.to_s] = desktop_file
          end
        rescue SystemCallError => e
          odebug "Failed to extract the desktop entries from #{source}: #{e}"
          {}
        end

        desktop_entry_dir = Pathname(ENV.fetch("HOMEBREW_XDG_DATA_HOME", "~/.local/share")).expand_path/"applications"
        desktop_entries.each_key do |desktop_entry_name|
          desktop_entry = desktop_entry_dir/desktop_entry_name
          next if !desktop_entry.exist? && !desktop_entry.symlink?

          message = "It seems there is already a desktop entry at '#{desktop_entry}'"
          # An upgrade rewrites the entry whatever it contains.
          raise CaskError, "#{message}. Use `--force` to overwrite." if !force && !adopt && !predecessor

          opoo "#{message}; overwriting."
        end

        super

        make_executable(target, command:)

        desktop_entries.each do |desktop_entry_name, desktop_file|
          desktop_entry_dir.mkpath
          desktop_entry = desktop_entry_dir/desktop_entry_name
          ohai "Creating desktop entry '#{desktop_entry}'"
          if desktop_entry.exist? || desktop_entry.symlink?
            # Take over the entry from any other cask that links to it,
            # so uninstalling that cask doesn't remove this one's entry.
            Caskroom.path.glob("*/*/*.desktop").each do |desktop_entry_link|
              desktop_entry_link.unlink if desktop_entry_link.symlink? && desktop_entry_link.readlink == desktop_entry
            end
            desktop_entry.unlink
          end
          desktop_entry.write(desktop_file.to_s)
          FileUtils.ln_sf desktop_entry, cask.staged_path/desktop_entry_name
        end

        # Update mimetype cache if possible
        return if desktop_entries.values.none? { |desktop_file| desktop_file.get("MimeType") }

        update_mime_info_cache(desktop_entry_dir, command:)
      end

      sig {
        override.params(
          skip:      T::Boolean,
          force:     T::Boolean,
          adopt:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, adopt: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        desktop_entry_dirs_with_mime_types = cask.staged_path
                                                 .glob("*.desktop")
                                                 .select(&:symlink?)
                                                 .filter_map do |desktop_entry_link|
          desktop_entry = desktop_entry_link.readlink
          desktop_entry_link.unlink
          next if !desktop_entry.exist? && !desktop_entry.symlink?

          mime_types = DesktopFileParser.new(desktop_entry.read).get("MimeType") if desktop_entry.file?
          ohai "Removing desktop entry '#{desktop_entry}'"
          desktop_entry.unlink
          desktop_entry.dirname if mime_types.present?
        end
        # Stop the mimetype cache from offering the removed entries
        desktop_entry_dirs_with_mime_types.uniq.each do |desktop_entry_dir|
          update_mime_info_cache(desktop_entry_dir, command:)
        end

        # Migration shim for the `Symlinked` -> `Moved` transition.
        # Old installs have the real AppImage in the versioned Caskroom `source`
        # and a symlink at `target` pointing back to it,
        # which `Moved#move_back` cannot reverse
        # (a non-forced uninstall errors; a skipping one leaves the target behind).
        # The old layout is identified by `target` being that back-symlink
        # (in the new layout, `target` is the real file),
        # regardless of whether `source` still exists:
        # the very breakage this stanza fixes
        # is a self-updater having already deleted the versioned `source`,
        # leaving `target` dangling. Reverse the old layout directly instead.
        # This can be removed once pre-transition installs have aged out.
        if target.symlink? && target.dirname.join(target.readlink) == source
          Utils.gain_permissions_remove(target, command:)
          # Preserve `source` during an upgrade
          # so that it is captured in the staged-directory backup
          # that `revert_upgrade` restores (and reinstalls from)
          # if the new install fails;
          # a successful upgrade purges that backup afterwards.
          Utils.gain_permissions_remove(source, command:) unless upgrade
          return
        end

        super
      end

      private

      DESKTOP_ENTRY_ICON_EXTENSIONS = %w[.svg .png .xpm].freeze
      private_constant :DESKTOP_ENTRY_ICON_EXTENSIONS

      # Far larger than any real desktop entry.
      DESKTOP_ENTRY_MAX_BYTES = T.let(64 * 1024, Integer)
      private_constant :DESKTOP_ENTRY_MAX_BYTES

      # Enough of an extensionless `.DirIcon` to find an SVG's `<svg` tag.
      DESKTOP_ENTRY_ICON_HEADER_BYTES = 1024
      private_constant :DESKTOP_ENTRY_ICON_HEADER_BYTES

      # Rebuild `desktop_entry_dir`'s mimetype cache, but only if there is one
      sig { params(desktop_entry_dir: Pathname, command: T.class_of(SystemCommand)).void }
      def update_mime_info_cache(desktop_entry_dir, command:)
        return unless (desktop_entry_dir/"mimeinfo.cache").exist?
        return unless (update_desktop_database = which("update-desktop-database"))

        command.run(update_desktop_database, args: [desktop_entry_dir], print_stderr: false)
      end

      sig { params(path: Pathname, command: T.class_of(SystemCommand)).void }
      def make_executable(path, command:)
        return if path.executable?

        if path.writable?
          FileUtils.chmod "+x", path
        else
          command.run!("chmod", args: ["+x", path], sudo: nil)
        end
      end

      # Extract the AppImage's top-level files and directories matching `pattern`
      # into `extract_root`, following top-level symlinks
      # (e.g. `app.desktop -> usr/share/...`) that `--appimage-extract` leaves dangling.
      # Callers check for the file type they need.
      sig { params(pattern: String, extract_root: Pathname, command: T.class_of(SystemCommand)).returns(T::Array[Pathname]) }
      def extract_from_appimage(pattern, extract_root:, command:)
        command.run(source, args: ["--appimage-extract", pattern], chdir: extract_root.dirname, print_stderr: false)

        extract_root.glob(pattern).sort.filter_map do |path|
          next path unless path.symlink?

          link = path.readlink.cleanpath
          # Skip any links that seem to point outside the image itself
          # They sometimes point to the developer's machine
          next if link.absolute? || link.descend.first.to_s == ".."

          command.run(source, args:         ["--appimage-extract", link.to_s],
                              chdir:        extract_root.dirname,
                              print_stderr: false)
          resolved_path = extract_root/link
          resolved_path if resolved_path.exist? && !resolved_path.symlink?
        end
      end
    end
  end
end
