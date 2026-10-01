# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Artifact
        module Moved
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Moved }

          sig { params(target: ::Pathname, source: ::Pathname).returns(T::Array[T.any(String, ::Pathname)]) }
          def backup_copy_args(target, source)
            # GNU `cp --reflink=auto` reduces I/O when the filesystem supports it.
            ["--reflink=auto", *super]
          end
        end
      end
    end
  end
end

Cask::Artifact::Moved.prepend(OS::Linux::Cask::Artifact::Moved)
