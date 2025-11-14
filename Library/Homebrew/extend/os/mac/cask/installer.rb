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
          return unless artifacts.any? do |artifact|
            ::Cask::Artifact::LINUX_ONLY_ARTIFACTS.include?(artifact.class)
          end

          raise ::Cask::CaskError, "Linux is required for this software."
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Mac::Cask::Installer)
