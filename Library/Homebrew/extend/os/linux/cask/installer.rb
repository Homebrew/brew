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
          return if artifacts.all? { |artifact| supported_artifact?(artifact) }

          raise ::Cask::CaskError, "macOS is required for this software."
        end

        private

        sig { params(artifact: ::Cask::Artifact::AbstractArtifact).returns(T::Boolean) }
        def supported_artifact?(artifact)
          return !artifact.manual_install if artifact.is_a?(::Cask::Artifact::Installer)

          ::Cask::Artifact::MACOS_ONLY_ARTIFACTS.exclude?(artifact.class)
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Linux::Cask::Installer)
