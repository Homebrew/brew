# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `mdimporter` stanza.
    class Mdimporter < Moved
      sig { override.returns(String) }
      def self.english_name
        "Spotlight metadata importer"
      end

      sig {
        override.params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
          options:      T.anything,
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        reinstall: false, command: SystemCommand, **options)
        super
        reload_spotlight(command:, **options)
      end

      private

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def reload_spotlight(command:, **_options)
        command.run!("/usr/bin/mdimport", args: ["-r", target])
      end
    end
  end
end
