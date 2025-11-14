# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cask
      module Artifact
        module Flatpak
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Flatpak }

          sig { params(command: T.untyped, verbose: T::Boolean, _options: T.untyped).void }
          def install_phase(command: nil, verbose: false, **_options)
            opoo "Flatpak artifacts are only supported on Linux"
          end

          sig { params(command: T.untyped, verbose: T::Boolean, _options: T.untyped).void }
          def uninstall_phase(command: nil, verbose: false, **_options)
            # No-op on macOS
          end
        end
      end
    end
  end
end

Cask::Artifact::Flatpak.prepend(OS::Mac::Cask::Artifact::Flatpak)
