# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cask
      module Artifact
        module Relocated
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Relocated }

          sig { returns(T::Boolean) }
          def altname_metadata_supported?
            true
          end
        end
      end
    end
  end
end

Cask::Artifact::Relocated.prepend(OS::Mac::Cask::Artifact::Relocated)
