# typed: strict
# frozen_string_literal: true

require "os/mac/ffi"

module OS
  module Mac
    module Cask
      module Utils
        module Trash
          TRASH_SCRIPT = T.let((HOMEBREW_LIBRARY_PATH/"cask/utils/trash.swift").freeze, ::Pathname)

          module ClassMethods
            include ::SystemCommand::Mixin

            sig {
              params(paths: ::Pathname, command: T.nilable(T.class_of(::SystemCommand)))
                .returns([T::Array[String], T::Array[String]])
            }
            def trash(*paths, command: nil)
              return swift_trash(*paths, command:) unless ffi_trash?

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

            private

            sig { returns(T::Boolean) }
            def ffi_trash?
              # TODO: Expand FFI trashing to all users when fully working.
              Homebrew::EnvConfig.developer?
            end

            sig {
              params(paths: ::Pathname, command: T.nilable(T.class_of(::SystemCommand)))
                .returns([T::Array[String], T::Array[String]])
            }
            def swift_trash(*paths, command: nil)
              return [[], []] if paths.empty?

              stdout = system_command(TRASH_SCRIPT,
                                      args:         paths,
                                      print_stderr: Homebrew::EnvConfig.developer?).stdout

              trashed, _, untrashable = stdout.partition("\n")
              trashed = trashed.split(":")
              untrashable = untrashable.split(":")

              trashed_with_permissions = T.let([], T::Array[String])
              still_untrashable = T.let([], T::Array[String])
              untrashable.each do |path|
                retried_stdout = T.let(nil, T.nilable(String))
                ::Cask::Utils.gain_permissions(::Pathname.new(path), ["-R"], ::SystemCommand) do
                  retried_stdout = system_command!(TRASH_SCRIPT,
                                                   args:         [path],
                                                   print_stderr: Homebrew::EnvConfig.developer?).stdout
                end

                retried_trashed, = retried_stdout.to_s.partition("\n")
                trashed_with_permissions.concat(retried_trashed.split(":"))
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
