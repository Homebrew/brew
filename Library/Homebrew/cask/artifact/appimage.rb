# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

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
        # Read the desktop entries from the staged AppImage
        # so a conflicting entry fails the install before anything is moved.

        # Quote special chars per the Desktop Entry `Exec` rules
        # Ref: https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html
        # then escape for its string type.
        # Only quote when the spec requires it: xdg-open's generic fallback splits `Exec`
        # on spaces and passes quote marks through literally.
        exec_path = if target.to_s.match?(/[\s"'\\<>~|&;$*?#()`]/)
          "\"#{target.to_s.gsub(/["`$\\]/) { |char| "\\#{char}" }}\""
            .gsub("\\") { "\\\\" }
            .gsub("%", "%%")
        else
          target.to_s.gsub("%", "%%")
        end

        # Some apps self-integrate their entries, which can be prevented by setting this var.
        # Ref: https://github.com/AppImage/AppImageSpec/blob/master/draft.md#desktop-integration
        # Spec says any non-empty value suffices, but some apps are more picky.
        exec_environment = "env DESKTOPINTEGRATION=1"

        make_executable(source, command:) if source.file?

        desktop_entries = Dir.mktmpdir("appimage-", HOMEBREW_TEMP) do |tmpdir|
          extract_root = Pathname(tmpdir)/"squashfs-root"

          extract_from_appimage("*.desktop", extract_root:, command:)
            .each_with_object({}) do |embedded_desktop_file, entries|
            # Not everything matching `*.desktop` is a desktop entry. E.g. opencode-desktop's
            # `ai.opencode.desktop` is its 228 MB executable and its entry is `ai.opencode.desktop.desktop`.
            # We assume an entry is valid iff the first non-empty non-comment line is exactly `[Desktop Entry]`
            # per spec. This matches GLib behavior.
            first_line = if embedded_desktop_file.file? && embedded_desktop_file.size <= DESKTOP_ENTRY_MAX_BYTES
              embedded_desktop_file.binread(DESKTOP_ENTRY_HEADER_BYTES).to_s.lines.map(&:strip)
                                   .find { |line| line.present? && !line.start_with?("#") }
            end
            if first_line != "[Desktop Entry]" # Assumes UTF-8, required by the spec
              odebug "Skipping '#{embedded_desktop_file.basename}' as it is not a desktop entry"
              next
            end

            # Look for the first `Icon` line
            lines = embedded_desktop_file.read.lines(chomp: true)
            icon_name = lines.filter_map { |line| line[/\AIcon\s*=\s*(.+)/, 1]&.strip }.first.to_s
            icon = extract_icon(icon_name, embedded_desktop_file.basename(".desktop").to_s, extract_root:, command:)

            contents = lines.filter_map do |line|
              case line
              when /\ATryExec\s*=/
                nil
              when /\AExec\s*=/
                "Exec=#{self.class.desktop_entry_exec(line.split("=", 2).fetch(1), exec_path:, exec_environment:)}"
              when /\AIcon\s*=/
                icon ? "Icon=#{icon}" : line
              else
                line
              end
            end
            if icon && lines.none? { |line| line.match?(/\AIcon\s*=/) } &&
               (desktop_entry_group_index = contents.index { |line| line.strip == "[Desktop Entry]" })
              contents.insert(desktop_entry_group_index + 1, "Icon=#{icon}")
            end

            entries[embedded_desktop_file.basename.to_s] = "#{contents.join("\n")}\n"
          end
        rescue SystemCallError => e
          odebug "Failed to extract the desktop entries from #{source}: #{e}"
          {}
        end

        if desktop_entries.empty?
          opoo "No desktop entry found in '#{target.basename}'; creating a minimal one."
          minimal_desktop_entry = [
            "[Desktop Entry]",
            "Type=Application",
            "Name=#{cask.name.first || cask.token}",
            ("Comment=#{cask.desc}" if cask.desc),
            "Exec=#{exec_environment} #{exec_path}",
          ]
          desktop_entries = { "#{cask.token}.desktop" => "#{minimal_desktop_entry.compact.join("\n")}\n" }
        end

        desktop_entry_dir = Pathname(ENV.fetch("HOMEBREW_XDG_DATA_HOME", "~/.local/share")).expand_path/"applications"
        desktop_entries.each_key do |desktop_entry_name|
          desktop_entry = desktop_entry_dir/desktop_entry_name
          next if !desktop_entry.exist? && !desktop_entry.symlink?

          message = "It seems there is already a desktop entry at '#{desktop_entry}'"
          # An upgrade rewrites the entry whatever it contains.
          raise CaskError, "#{message}." if !force && !adopt && !predecessor

          opoo "#{message}; overwriting."
        end

        super

        make_executable(target, command:)

        desktop_entry_dir.mkpath
        desktop_entries.each do |desktop_entry_name, desktop_entry_contents|
          desktop_entry = desktop_entry_dir/desktop_entry_name
          ohai "Creating desktop entry '#{desktop_entry}'"
          desktop_entry.unlink if desktop_entry.exist? || desktop_entry.symlink?
          desktop_entry.write(desktop_entry_contents)
          FileUtils.ln_sf desktop_entry, cask.staged_path/desktop_entry_name
        end

        # Update mimetype cache if possible
        return if desktop_entries.values.grep(/^MimeType\s*=/).empty?
        return unless (desktop_entry_dir/"mimeinfo.cache").exist?
        return unless (update_desktop_database = which("update-desktop-database"))

        command.run(update_desktop_database, args: [desktop_entry_dir], print_stderr: false)
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
        cask.staged_path.glob("*.desktop").select(&:symlink?).each do |desktop_entry_link|
          desktop_entry = desktop_entry_link.readlink
          if desktop_entry.exist? || desktop_entry.symlink?
            ohai "Removing desktop entry '#{desktop_entry}'"
            desktop_entry.unlink
          end
          desktop_entry_link.unlink
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

      # Rewrite a desktop entry's `Exec` value to run `exec_path` with `exec_environment`,
      # keeping the variables and arguments of the program it replaces.
      sig { params(exec: String, exec_path: String, exec_environment: String).returns(String) }
      def self.desktop_entry_exec(exec, exec_path:, exec_environment:)
        # We want `Exec` to be the absolute path to the AppImage <target>,
        # keeping the entry's environment and arguments, e.g.
        #   Input:  Exec=env GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 audacity %F
        #   Output: Exec=env DESKTOPINTEGRATION=1 GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 <target> %F
        #
        #   Input:  Exec=LD_LIBRARY_PATH=usr/lib clashmi %u
        #   Output: Exec=env DESKTOPINTEGRATION=1 LD_LIBRARY_PATH=usr/lib <target> %u
        #
        #   Input:  Exec=AppRun --no-sandbox %U
        #   Output: Exec=env DESKTOPINTEGRATION=1 <target> --no-sandbox %U
        #
        #   Input:  Exec="Shutter Encoder"
        #   Output: Exec=env DESKTOPINTEGRATION=1 <target>
        words = exec.scan(/(?:"(?:\\.|[^"\\])*"|'[^']*'|[^\s"])+/).map(&:to_s)
        words.shift if words.first == "env"
        variables = words.take_while { |word| word.match?(/\A[A-Za-z_]\w*=/) }
        arguments = words.drop(variables.length + 1)
        variables.reject! { |variable| variable.start_with?("DESKTOPINTEGRATION=") }
        [exec_environment, *variables, exec_path, *arguments].join(" ")
      end

      private

      DESKTOP_ENTRY_ICON_EXTENSIONS = %w[.svg .png .xpm].freeze
      private_constant :DESKTOP_ENTRY_ICON_EXTENSIONS

      # Far larger than any real desktop entry.
      DESKTOP_ENTRY_MAX_BYTES = T.let(64 * 1024, Integer)
      private_constant :DESKTOP_ENTRY_MAX_BYTES

      # Enough of a candidate desktop entry to find its first group header.
      DESKTOP_ENTRY_HEADER_BYTES = T.let(4 * 1024, Integer)
      private_constant :DESKTOP_ENTRY_HEADER_BYTES

      # Enough of an extensionless `.DirIcon` to find an SVG's `<svg` tag.
      DESKTOP_ENTRY_ICON_HEADER_BYTES = 1024
      private_constant :DESKTOP_ENTRY_ICON_HEADER_BYTES

      sig { params(path: Pathname, command: T.class_of(SystemCommand)).void }
      def make_executable(path, command:)
        return if path.executable?

        if path.writable?
          FileUtils.chmod "+x", path
        else
          command.run!("chmod", args: ["+x", path], sudo: nil)
        end
      end

      # Find the icon `icon_name` refers to at the top of the AppImage, falling back to its
      # `.DirIcon`, and copy it into the versioned Caskroom as `<icon_stem><extension>`.
      sig {
        params(icon_name: String, icon_stem: String, extract_root: Pathname,
               command: T.class_of(SystemCommand)).returns(T.nilable(Pathname))
      }
      def extract_icon(icon_name, icon_stem, extract_root:, command:)
        icon_name_extension = File.extname(icon_name)
        # Entry spec allows either a bare name, name with extension, or an absolute path
        # Relative paths are meaningless since the desktop file can be located anywhere
        # Absolute paths are meaningless inside an AppImage and usually point to developer's machine
        # According to AppImage spec, it should name a file located in the root of the image
        icon_patterns = if icon_name.empty? || icon_name.include?("/")
          []
        elsif DESKTOP_ENTRY_ICON_EXTENSIONS.include?(icon_name_extension)
          [icon_name, "#{icon_name.delete_suffix(icon_name_extension)}.*"]
        else
          ["#{icon_name}.*"]
        end
        embedded_icon = icon_patterns.lazy.filter_map do |pattern|
          paths = extract_from_appimage(pattern, extract_root:, command:).select(&:file?)
          DESKTOP_ENTRY_ICON_EXTENSIONS.lazy.filter_map { |ext| paths.find { |path| path.extname == ext } }.first
        end.first
        # Fallback to .DirIcon which is defined in the AppImage spec
        embedded_icon ||= extract_from_appimage(".DirIcon", extract_root:, command:).find(&:file?)
        return unless embedded_icon

        icon_extension = if DESKTOP_ENTRY_ICON_EXTENSIONS.include?(embedded_icon.extname)
          embedded_icon.extname
        else
          # Infer .DirIcon's file type
          case embedded_icon.binread(DESKTOP_ENTRY_ICON_HEADER_BYTES)
          when /\A\x89PNG/n then ".png"
          when /<svg/ then ".svg"
          when %r{\A/\* XPM \*/} then ".xpm"
          end
        end
        return unless icon_extension

        icon = cask.staged_path/"#{icon_stem}#{icon_extension}"
        FileUtils.cp embedded_icon, icon
        icon
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
