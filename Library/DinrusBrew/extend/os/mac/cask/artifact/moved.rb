# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module Artifact
        module Moved
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Moved }

          sig { params(target: Pathname).returns(T::Boolean) }
          def undeletable?(target)
            MacOS.undeletable?(target)
          end
        end
      end
    end
  end
end

Cask::Artifact::Moved.prepend(OS::Mac::Cask::Artifact::Moved)
