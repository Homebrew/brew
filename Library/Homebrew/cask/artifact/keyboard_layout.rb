# typed: true
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `keyboard_layout` stanza.
    #
    # @api private
    class KeyboardLayout < Moved
      def install_phase(**options)
        super(**options)
        delete_keyboard_layout_cache(**options)
      end

      def uninstall_phase(**options)
        super(**options)
        delete_keyboard_layout_cache(**options)
      end

      private

      def delete_keyboard_layout_cache(command: nil, **_)
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
