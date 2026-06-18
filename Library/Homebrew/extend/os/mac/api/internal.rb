# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module API
      module Internal
        module ClassMethods
          extend T::Helpers

          requires_ancestor { T.class_of(::Homebrew::API::Internal) }

          private

          sig { returns(Utils::Bottles::Tag) }
          def fallback_tag
            if MacOS.version.prerelease?
              # When a new macOS version has been announced, we won't have generated a JSON file for it yet.
              # We need to fallback to allow us to test that macOS version.
              fallback_os = ::MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
              ::Utils::Bottles::Tag.new(system: fallback_os, arch: ::Hardware::CPU.arch)
            else
              effective_tag
            end
          end
        end
      end
    end
  end
end

Homebrew::API::Internal.singleton_class.prepend(OS::Mac::API::Internal::ClassMethods)
