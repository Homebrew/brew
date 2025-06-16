# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Artifact
        module Moved
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Moved }

          sig { params(target: Pathname).returns(T::Boolean) }
          def undeletable?(target)
            !target.parent.writable?
          end
        end
      end
    end
  end
end

Cask::Artifact::Moved.prepend(OS::Linux::Cask::Artifact::Moved)
