# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module Artifact
        module AbstractUninstall
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::AbstractUninstall }

          sig { params(target: Pathname).returns(T::Boolean) }
          def undeletable?(target)
            MacOS.undeletable?(target)
          end
        end
      end
    end
  end
end

Cask::Artifact::AbstractUninstall.prepend(OS::Mac::Cask::Artifact::AbstractUninstall)
