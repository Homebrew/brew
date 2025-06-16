# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Artifact
        module Symlinked
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::Symlinked }

          sig { params(command: T.class_of(SystemCommand)).void }
          def create_filesystem_link(command)
            ::Cask::Utils.gain_permissions_mkpath(target.dirname, command:)

            command.run! "/bin/ln", args: ["--no-dereference", "--force", "--symbolic", source, target],
                                    sudo: !target.dirname.writable?
          end
        end
      end
    end
  end
end

Cask::Artifact::Symlinked.prepend(OS::Linux::Cask::Artifact::Symlinked)
