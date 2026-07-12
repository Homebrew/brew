# typed: strict
# frozen_string_literal: true

require "os/mac/ffi"

module OS
  module Mac
    module Cask
      module Quarantine
        COPY_XATTRS_RUBY = "require \"os/mac/ffi\"; MacOS::FFI.copy_xattrs(ARGV.fetch(0), ARGV.fetch(1))"

        module ClassMethods
          extend T::Helpers
          include Kernel
          include ::Utils::Output::Mixin

          requires_ancestor { ::Cask::Quarantine }

          sig { returns([Symbol, T.nilable(String)]) }
          def check_quarantine_support
            return super unless ffi_quarantine?

            odebug "Checking quarantine support"

            status = if ::Cask::Quarantine.xattr_available?
              odebug "Quarantine is available via FFI."
              :quarantine_available
            else
              odebug "There's no working version of `xattr` on this system."
              :xattr_broken
            end
            [status, nil]
          end

          sig {
            params(file: T.any(String, ::Pathname))
              .returns(T.nilable(::Cask::Quarantine::SigningIdentity))
          }
          def signing_identity(file)
            requirement = MacOS::FFI::Security.designated_requirement(file.to_s)
            return if requirement.nil?

            ::Cask::Quarantine::SigningIdentity.new(requirement:)
          end

          sig {
            params(
              file:     T.any(String, ::Pathname),
              identity: ::Cask::Quarantine::SigningIdentity,
            ).returns(T.nilable(T::Boolean))
          }
          def signing_identity_match(file, identity)
            MacOS::FFI::Security.requirement_match(file.to_s, identity.requirement)
          end

          sig { params(cask: T.nilable(::Cask::Cask), download_path: T.nilable(::Pathname), action: T::Boolean).void }
          def cask!(cask: nil, download_path: nil, action: true)
            return super unless ffi_quarantine?
            return if cask.nil? || download_path.nil?

            return if ::Cask::Quarantine.detect(download_path)

            odebug "Quarantining #{download_path}"

            path_cf_string = MacOS::FFI::CoreFoundation.string_create(download_path.to_s)
            if path_cf_string.null?
              Kernel.raise ::Cask::CaskQuarantineError.new(download_path,
                                                           "Failed to create CFString for path")
            end

            path_cf_url = MacOS::FFI::CoreFoundation.url_create_with_file_system_path(path_cf_string)
            if path_cf_url.null?
              Kernel.raise ::Cask::CaskQuarantineError.new(download_path,
                                                           "Failed to create CFURL for path")
            end

            quarantine_agent_name = MacOS::FFI::CoreFoundation.string_create("Homebrew Cask")
            quarantine_data_url = MacOS::FFI::CoreFoundation.string_create(cask.url.to_s)
            quarantine_origin_url = MacOS::FFI::CoreFoundation.string_create(cask.homepage.to_s)
            if quarantine_agent_name.null? || quarantine_data_url.null? || quarantine_origin_url.null?
              Kernel.raise ::Cask::CaskQuarantineError.new(download_path,
                                                           "Failed to create CFString for quarantine properties")
            end

            quarantine_dictionary = MacOS::FFI::CoreFoundation.dictionary_create(
              MacOS::FFI::LaunchServices.quarantine_agent_name_key => quarantine_agent_name,
              MacOS::FFI::LaunchServices.quarantine_type_key       => MacOS::FFI::LaunchServices.quarantine_type_web_download,
              MacOS::FFI::LaunchServices.quarantine_data_url_key   => quarantine_data_url,
              MacOS::FFI::LaunchServices.quarantine_origin_url_key => quarantine_origin_url,
            )
            if quarantine_dictionary.null?
              Kernel.raise ::Cask::CaskQuarantineError.new(download_path, "Failed to create quarantine dictionary")
            end

            success = MacOS::FFI::CoreFoundation.url_set_resource_property_for_key(
              path_cf_url,
              MacOS::FFI::CoreFoundation.url_quarantine_properties_key,
              quarantine_dictionary,
            )

            return if success

            Kernel.raise ::Cask::CaskQuarantineError.new(download_path, "Failed to set quarantine properties for URL")
          end

          sig { params(from: ::Pathname, to: ::Pathname, command: T.class_of(::SystemCommand)).void }
          def copy_xattrs(from, to, command:)
            odebug "Copying xattrs from #{from} to #{to}"
            return super unless ffi_quarantine?

            if to.writable?
              MacOS::FFI.copy_xattrs(from.to_s, to.to_s)
              return
            end

            command.run!(
              HOMEBREW_BREW_FILE,
              args: [
                "ruby",
                "--",
                "-e",
                COPY_XATTRS_RUBY,
                from,
                to,
              ],
              sudo: true,
            )
          end

          private

          sig { returns(T::Boolean) }
          def ffi_quarantine?
            # TODO: Expand FFI quarantine and xattr copying to all users when fully working.
            Homebrew::EnvConfig.developer?
          end
        end
      end
    end
  end
end

Cask::Quarantine.singleton_class.prepend(OS::Mac::Cask::Quarantine::ClassMethods)
