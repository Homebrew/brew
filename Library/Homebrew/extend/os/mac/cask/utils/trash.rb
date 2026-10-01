# typed: strict
# frozen_string_literal: true

require "os/mac/ffi"

module OS
  module Mac
    module Cask
      module Utils
        module Trash
          module ClassMethods
            sig {
              params(paths: ::Pathname, command: T.nilable(T.class_of(::SystemCommand)))
                .returns([T::Array[String], T::Array[String]])
            }
            def trash(*paths, command: nil)
              trashed, untrashable = MacOS::FFI::Foundation.trash_paths(paths.map(&:to_s))

              trashed_with_permissions = T.let([], T::Array[String])
              still_untrashable = T.let([], T::Array[String])
              untrashable.each do |path|
                destination = T.let(nil, T.nilable(String))
                ::Cask::Utils.gain_permissions(::Pathname.new(path), ["-R"], ::SystemCommand) do
                  destination = MacOS::FFI::Foundation.trash_item(path)
                  Kernel.raise if destination.nil?
                end

                if destination.nil?
                  still_untrashable << path
                else
                  trashed_with_permissions << destination
                end
              rescue
                still_untrashable << path
              end

              [trashed + trashed_with_permissions, still_untrashable]
            end
          end
        end
      end
    end
  end
end

Cask::Utils::Trash.singleton_class.prepend(OS::Mac::Cask::Utils::Trash::ClassMethods)
