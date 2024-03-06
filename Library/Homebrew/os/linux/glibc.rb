# typed: true
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying `glibc` information.
    module Glibc
      module_function

      sig { returns(Version) }
      def system_version
        @system_version ||= begin
          version = Utils.popen_read("/usr/bin/ldd", "--version")[/ (\d+\.\d+)/, 1]
          if version
            Version.new version
          else
            Version::NULL
          end
        end
      end

      sig { returns(Version) }
      def version
        @version ||= begin
          version = Utils.popen_read(HOMEBREW_PREFIX/"opt/glibc/bin/ldd", "--version")[/ (\d+\.\d+)/, 1]
          if version
            Version.new version
          else
            system_version
          end
        end
      end

      sig { returns(Version) }
      def minimum_version
        Version.new(ENV.fetch("HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION"))
      end

      sig { returns(T::Boolean) }
      def below_minimum_version?
        system_version < minimum_version
      end

      sig { returns(T::Boolean) }
      def below_ci_version?
        system_version < LINUX_GLIBC_CI_VERSION
      end
    end
  end
end
