# typed: strict
# frozen_string_literal: true

require "cask/macos"
require "os/mac/ffi"

module OS
  module Mac
    module Cask
      module Artifact
        module AbstractUninstall
          extend T::Helpers

          requires_ancestor { ::Cask::Artifact::AbstractUninstall }

          sig { params(target: ::Pathname).returns(T::Boolean) }
          def undeletable?(target)
            MacOS.undeletable?(target)
          end

          module ClassMethods
            sig { params(pid: Integer).returns(T.nilable(Integer)) }
            def parent_pid(pid)
              MacOS::FFI::LibProc.parent_pid(pid)
            end

            sig { params(pid: Integer).returns(T.nilable(String)) }
            def bundle_identifier_for_pid(pid)
              MacOS::FFI::AppKit.bundle_identifier_for_pid(pid)
            end

            sig { params(pid: Integer).returns(T.nilable(Integer)) }
            def owner_uid(pid)
              MacOS::FFI::LibProc.real_uid(pid)
            end
          end
        end
      end
    end
  end
end

Cask::Artifact::AbstractUninstall.prepend(OS::Mac::Cask::Artifact::AbstractUninstall)
Cask::Artifact::AbstractUninstall.singleton_class.prepend(OS::Mac::Cask::Artifact::AbstractUninstall::ClassMethods)
