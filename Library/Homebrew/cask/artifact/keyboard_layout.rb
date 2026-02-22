# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `keyboard_layout` stanza.
    class KeyboardLayout < Moved
      sig { override.params(command: T.class_of(SystemCommand), options: T.anything).void }
      def install_phase(command:, **options)
        super
        delete_keyboard_layout_cache(**options)
      end

      sig { override.params(command: T.class_of(SystemCommand), options: T.anything).void }
      def uninstall_phase(command:, **options)
        super
        delete_keyboard_layout_cache(**options)
      end

      private

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def delete_keyboard_layout_cache(command:, **_options)
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
