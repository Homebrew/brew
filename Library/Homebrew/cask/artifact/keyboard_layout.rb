# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `keyboard_layout` stanza.
    class KeyboardLayout < Moved
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
        super
        delete_keyboard_layout_cache(command:)
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
        super
        delete_keyboard_layout_cache(command:)
      end

      private

      sig { params(command: T.class_of(SystemCommand)).void }
      def delete_keyboard_layout_cache(command: SystemCommand)
        command.run!(
          "/bin/rm",
          args:         ["-f", "--", "/System/Library/Caches/com.apple.IntlDataCache.le*"],
          sudo:         true,
          sudo_as_root: true,
        )
      end
    end
  end
end
