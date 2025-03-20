# typed: strict
# frozen_string_literal: true

module Utils
  module Bottles
    class << self
      module MacOSOverride
        sig { params(tag: T.nilable(T.any(Symbol, Tag))).returns(Tag) }
        def tag(tag = nil)
          return Tag.new(system: MacOS.version.to_sym, arch: Hardware::CPU.arch) if tag.nil?

          super
        end

        # Determines if bottle relocation should be skipped for Apple Silicon with default prefix
        sig { params(keg: T.nilable(Keg)).returns(T::Boolean) }
        def skip_relocation_for_apple_silicon?(_keg = nil)
          return false unless Hardware::CPU.arm?
          return false unless HOMEBREW_PREFIX.to_s == HOMEBREW_MACOS_ARM_DEFAULT_PREFIX

          # First check if enabled by env var for gradual rollout
          return true if ENV.fetch("HOMEBREW_BOTTLE_SKIP_RELOCATION_ARM64", "false") == "true"

          # If not explicitly enabled by env var, check if binaries need relocation
          return false unless keg

          !binaries_need_relocation?(keg)
        end

        # Determines if binary files in a keg need relocation
        sig { params(keg: Keg).returns(T::Boolean) }
        def binaries_need_relocation?(keg)
          keg.mach_o_files.any? do |file|
            # Check if dylib ID contains paths that need relocation
            (file.dylib? && file.dylib_id&.include?(HOMEBREW_MACOS_ARM_DEFAULT_PREFIX)) ||
            # Check if linked libraries contain paths that need relocation
            file.dynamically_linked_libraries.any? { |lib| lib.include?(HOMEBREW_MACOS_ARM_DEFAULT_PREFIX) }
          end
        end
      end

      prepend MacOSOverride
    end

    class Collector
      private

      alias generic_find_matching_tag find_matching_tag

      sig { params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean).returns(T.nilable(Utils::Bottles::Tag)) }
      def find_matching_tag(tag, no_older_versions: false)
        # Used primarily by developers testing beta macOS releases.
        if no_older_versions ||
           (OS::Mac.version.prerelease? &&
            Homebrew::EnvConfig.developer? &&
            Homebrew::EnvConfig.skip_or_later_bottles?)
          generic_find_matching_tag(tag)
        else
          generic_find_matching_tag(tag) ||
            find_older_compatible_tag(tag)
        end
      end

      # Find a bottle built for a previous version of macOS.
      sig { params(tag: Utils::Bottles::Tag).returns(T.nilable(Utils::Bottles::Tag)) }
      def find_older_compatible_tag(tag)
        tag_version = begin
          tag.to_macos_version
        rescue MacOSVersion::Error
          nil
        end

        return if tag_version.blank?

        tags.find do |candidate|
          next if candidate.arch != tag.arch

          candidate.to_macos_version <= tag_version
        rescue MacOSVersion::Error
          false
        end
      end
    end
  end
end
