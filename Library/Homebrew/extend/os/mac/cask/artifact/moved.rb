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

          sig { params(target: ::Pathname).returns(T::Boolean) }
          def undeletable?(target)
            MacOS.undeletable?(target)
          end

          sig { params(target: ::Pathname, source: ::Pathname).returns(T::Array[T.any(String, ::Pathname)]) }
          def backup_copy_args(target, source)
            args = super

            return args if MacOS.version < :sonoma
            return args if target.stat.dev != source.dirname.stat.dev

            ["-c", *args]
          end
        end
      end
    end
  end
end

Cask::Artifact::Moved.prepend(OS::Mac::Cask::Artifact::Moved)
