# typed: strict
# frozen_string_literal: true

require "os/linux/ld"

module OS
  module Linux
    # Helper functions for querying `libstdc++` information.
    module Libstdcxx
      SOVERSION = 6
      SONAME = T.let("libstdc++.so.#{SOVERSION}".freeze, String)

      sig { returns(T::Boolean) }
      def self.below_ci_version?
        system_version < LINUX_LIBSTDCXX_CI_VERSION
      end

      sig { returns(Version) }
      def self.system_version
        @system_version ||= T.let(nil, T.nilable(Version))
        @system_version ||= if (path = system_path)
          Version.new("#{SOVERSION}#{path.realpath.basename.to_s.delete_prefix!(SONAME)}")
        else
          Version::NULL
        end
      end

      sig { returns(T.nilable(::Pathname)) }
      def self.system_path
        @system_path ||= T.let(nil, T.nilable(::Pathname))
        @system_path ||= find_library(OS::Linux::Ld.library_paths(brewed: false))
        @system_path ||= find_library(OS::Linux::Ld.system_dirs(brewed: false))
      end

      sig { params(paths: T::Array[String]).returns(T.nilable(::Pathname)) }
      private_class_method def self.find_library(paths)
        paths.each do |path|
          next if path.start_with?(HOMEBREW_PREFIX)

          candidate = Pathname(path)/SONAME
          elf_candidate = ELFPathname.wrap(candidate)
          return candidate if candidate.exist? && elf_candidate.elf?
        end
        nil
      end
    end
  end
end
