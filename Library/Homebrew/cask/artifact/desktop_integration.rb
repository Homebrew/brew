# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "cask/desktop_file_parser"

module Cask
  module Artifact
    # Installs and removes the desktop entries that `AppImage` and `DesktopEntry` prepare.
    module DesktopIntegration
      extend T::Helpers

      requires_ancestor { AbstractArtifact }

      private

      sig { returns(Pathname) }
      def desktop_entry_dir
        Pathname(ENV.fetch("HOMEBREW_XDG_DATA_HOME", "~/.local/share")).expand_path/"applications"
      end

      sig {
        params(desktop_entry_names: T::Array[String], force: T::Boolean, adopt: T::Boolean,
               predecessor: T.nilable(Cask)).void
      }
      def refuse_taken_desktop_entries(desktop_entry_names, force:, adopt:, predecessor:)
        desktop_entry_names.each do |desktop_entry_name|
          desktop_entry = desktop_entry_dir/desktop_entry_name
          next if !desktop_entry.exist? && !desktop_entry.symlink?

          message = "It seems there is already a desktop entry at '#{desktop_entry}'"
          # An upgrade rewrites the entry whatever it contains.
          raise CaskError, "#{message}. Use `--force` to overwrite." if !force && !adopt && !predecessor

          opoo "#{message}; overwriting."
        end
      end

      sig { params(desktop_entries: T::Hash[String, DesktopFileParser], command: T.class_of(SystemCommand)).void }
      def write_desktop_entries(desktop_entries, command:)
        replaces_mime_types = T.let(false, T::Boolean)
        desktop_entries.each do |desktop_entry_name, desktop_file|
          desktop_entry_dir.mkpath
          desktop_entry = desktop_entry_dir/desktop_entry_name
          ohai "Creating desktop entry '#{desktop_entry}'"
          if desktop_entry.exist? || desktop_entry.symlink?
            replaces_mime_types ||= desktop_entry.file? &&
                                    DesktopFileParser.new(desktop_entry.read).get("MimeType").present?
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
        return if !replaces_mime_types && desktop_entries.values.none? { |desktop_file| desktop_file.get("MimeType") }

        update_mime_info_cache(desktop_entry_dir, command:)
      end

      sig { params(desktop_entry_links: T::Array[Pathname], command: T.class_of(SystemCommand)).void }
      def remove_desktop_entries(desktop_entry_links, command:)
        applications_dirs_with_mime_types = desktop_entry_links.select(&:symlink?).filter_map do |desktop_entry_link|
          desktop_entry = desktop_entry_link.readlink
          # Leave the staged archive's own links: `write_desktop_entries` links each entry by its absolute path.
          next if !desktop_entry.absolute? || desktop_entry.basename != desktop_entry_link.basename

          desktop_entry_link.unlink
          next if !desktop_entry.exist? && !desktop_entry.symlink?

          mime_types = DesktopFileParser.new(desktop_entry.read).get("MimeType") if desktop_entry.file?
          ohai "Removing desktop entry '#{desktop_entry}'"
          desktop_entry.unlink
          desktop_entry.dirname if mime_types.present?
        end
        # Stop the mimetype cache from offering the removed entries
        applications_dirs_with_mime_types.uniq.each do |applications_dir|
          update_mime_info_cache(applications_dir, command:)
        end
      end

      # Rebuild `applications_dir`'s mimetype cache, but only if there is one
      sig { params(applications_dir: Pathname, command: T.class_of(SystemCommand)).void }
      def update_mime_info_cache(applications_dir, command:)
        return unless (applications_dir/"mimeinfo.cache").exist?
        return unless (update_desktop_database = which("update-desktop-database"))

        command.run(update_desktop_database, args: [applications_dir], print_stderr: false)
      end
    end
  end
end
