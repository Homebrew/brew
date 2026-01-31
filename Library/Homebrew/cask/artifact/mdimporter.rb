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
          successor:    T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(
        adopt: false,
        auto_updates: false,
        force: false,
        verbose: false,
        predecessor: nil,
        successor: nil,
        reinstall: false,
        command: SystemCommand
      )
        super
        reload_spotlight(command:)
      end

      private

      sig { params(command: T.class_of(SystemCommand)).void }
      def reload_spotlight(command:)
        command.run!("/usr/bin/mdimport", args: ["-r", target])
      end
    end
  end
end
