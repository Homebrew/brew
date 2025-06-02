# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Installer
        private

        extend T::Helpers

        requires_ancestor { ::Cask::Installer }

        sig { void }
        def check_stanza_os_requirements
          return if artifacts.all?(::Cask::Artifact::Font)

          raise ::Cask::CaskError, "Для этого ПО требуется macOS."
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Linux::Cask::Installer)
