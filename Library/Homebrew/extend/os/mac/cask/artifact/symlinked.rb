# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module Artifact
        module Symlinked
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Symlinked }

          sig { params(command: T.class_of(SystemCommand)).void }
          def create_filesystem_link(command)
            ::Cask::Utils.gain_permissions_mkpath(target.dirname, command:)

            command.run! "/bin/ln", args: ["-h", "-f", "-s", "--", source, target],
                                    sudo: !target.dirname.writable?

            add_altname_metadata(source, target.basename, command:)
          end
        end
      end
    end
  end
end

Cask::Artifact::Symlinked.prepend(OS::Mac::Cask::Artifact::Symlinked)
