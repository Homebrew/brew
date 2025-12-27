# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cask
      module Installer
        extend T::Helpers

        requires_ancestor { ::Cask::Installer }

        sig { void }
        def check_stanza_os_requirements
          cask = T.unsafe(instance_variable_get(:@cask))
          return if cask.supports_macos? != false

          raise ::Cask::CaskError, "Linux is required for this software."
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Mac::Cask::Installer)
