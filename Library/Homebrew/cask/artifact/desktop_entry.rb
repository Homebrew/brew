# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "cask/artifact/desktop_entries_handling"
require "cask/desktop_file_parser"

module Cask
  module Artifact
    # Artifact corresponding to the `desktop_entry` stanza.
    class DesktopEntry < AbstractArtifact
      include DesktopEntriesHandling

      PREFIXED_DESKTOP_ENTRY_PATH = %r{\A(?<prefix>(?:[^/]+/)*)share/applications/[^/]+\.desktop\z}
      private_constant :PREFIXED_DESKTOP_ENTRY_PATH

      ICON_PATTERN = "share/icons/hicolor/*/apps/*.{svg,png,xpm}"
      private_constant :ICON_PATTERN

      sig { params(cask: Cask, path: T.any(String, Pathname)).returns(T.attached_class) }
      def self.from_args(cask, path) = new(cask, path)

      sig { params(cask: Cask, path: T.any(String, Pathname)).void }
      def initialize(cask, path)
        super
        @path_string = T.let(path.to_s, String)
        prefix = @path_string[PREFIXED_DESKTOP_ENTRY_PATH, :prefix]
        if prefix.nil? || Pathname(path).each_filename.any?("..")
          raise CaskInvalidError.new(cask, "'desktop_entry' requires a path within the staged cask " \
                                           "ending in 'share/applications/<name>.desktop'")
        end

        @prefix_string = T.let(prefix, String)
      end

      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        source = cask.staged_path/@path_string
        unless source.file?
          raise CaskError, "It seems the #{self.class.english_name} source '#{source}' is not there."
        end
        unless source.realpath.ascend.include?(cask.staged_path.realpath)
          raise CaskError, "The desktop entry '#{source}' links outside '#{cask.staged_path}'."
        end

        desktop_file = DesktopFileParser.new(source.read)
        raise CaskError, "'#{source}' is not a desktop entry." unless desktop_file.desktop_entry?

        prefix = cask.staged_path/@prefix_string
        begin
          desktop_file.replace_program do |embedded_program|
            program = prefix/"bin"/File.basename(embedded_program)
            unless program.file?
              raise CaskError,
                    "The desktop entry '#{source}' runs '#{embedded_program}', which is not at '#{program}'."
            end

            program.to_s
          end
        rescue ArgumentError => e
          raise CaskError, "The desktop entry '#{source}' has a malformed `Exec`: #{e}"
        end

        desktop_file.update("Icon") do |icon_name|
          next icon_name if icon_name.blank? || icon_name.include?("/")

          icons = prefix.glob(ICON_PATTERN).select { |path| path.basename(".*").to_s == icon_name }
          icon = icons.max_by do |path|
            size = path.dirname.dirname.basename.to_s
            (size == "scalable") ? Float::INFINITY : size.to_i
          end
          icon&.to_s || icon_name
        end

        desktop_entry_name = source.basename.to_s
        refuse_taken_desktop_entries([desktop_entry_name], force:, adopt:, predecessor:)
        write_desktop_entries({ desktop_entry_name => desktop_file }, command:)
      end

      sig {
        params(
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
        remove_desktop_entries([cask.staged_path/File.basename(@path_string)], command:)
      end

      sig { override.returns(String) }
      def summarize = @path_string
    end
  end
end
