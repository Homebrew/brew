# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Artifact
        module Relocated
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Relocated }

          sig { params(file: ::Pathname, altname: ::Pathname, command: T.class_of(SystemCommand)).returns(T.nilable(SystemCommand::Result)) }
          def add_altname_metadata(file, altname, command:)
            # no-op on Linux: /usr/bin/xattr for setting extended attributes is not available there.
          end
        end
      end
    end
  end
end

Cask::Artifact::Relocated.prepend(OS::Linux::Cask::Artifact::Relocated)
