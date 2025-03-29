# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Installer
        extend T::Helpers

        requires_ancestor { ::Cask::Installer }

        LINUX_INVALID_ARTIFACTS = [
          ::Cask::Artifact::App,
          ::Cask::Artifact::AudioUnitPlugin,
          ::Cask::Artifact::Colorpicker,
          ::Cask::Artifact::Dictionary,
          ::Cask::Artifact::InputMethod,
          ::Cask::Artifact::Installer,
          ::Cask::Artifact::InternetPlugin,
          ::Cask::Artifact::KeyboardLayout,
          ::Cask::Artifact::Mdimporter,
          ::Cask::Artifact::Pkg,
          ::Cask::Artifact::Prefpane,
          ::Cask::Artifact::Qlplugin,
          ::Cask::Artifact::ScreenSaver,
          ::Cask::Artifact::Service,
          ::Cask::Artifact::Suite,
          ::Cask::Artifact::VstPlugin,
          ::Cask::Artifact::Vst3Plugin,
        ].freeze

        sig { void }
        def check_stanza_os_requirements
          return unless artifacts.any? do |artifact|
            LINUX_INVALID_ARTIFACTS.include?(artifact.class)
          end

          raise ::Cask::CaskError, "macOS is required for this software."
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Linux::Cask::Installer)
