# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Installer
        extend T::Helpers

        requires_ancestor { ::Cask::Installer }

        sig { void }
        def check_stanza_os_requirements
          return if cask.supports_linux?

          raise ::Cask::CaskError, "#{cask}: This cask requires macOS."
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Linux::Cask::Installer)
