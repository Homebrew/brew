# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  class Dmg
    module MacOSDmgExtension
      # `hdiutil` is deprecated on macOS 27. Before macOS 27.2, `diskutil image` ignores standard
      # input and blocks on a GUI prompt for a license agreement instead of cancelling.
      sig { returns(T::Boolean) }
      def diskutil_image?
        MacOS.full_version >= "27.2"
      end
    end
    private_constant :MacOSDmgExtension

    singleton_class.prepend MacOSDmgExtension
  end
end
