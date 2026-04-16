# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `qlplugin` stanza.
    class Qlplugin < Moved
      sig { override.returns(String) }
      def self.english_name
        "Quick Look Plugin"
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
          options:      T.anything,
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        successor: nil, reinstall: false, command: SystemCommand, **options)
        super
        reload_quicklook(command:)
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
          options:   T.anything,
        ).void
      }
      def uninstall_phase(skip: false, force: false, adopt: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand, **options)
        super
        reload_quicklook(command:)
      end

      private

      sig { params(command: T.class_of(SystemCommand)).void }
      def reload_quicklook(command: SystemCommand)
        command.run!("/usr/bin/qlmanage", args: ["-r"])
      end
    end
  end
end
