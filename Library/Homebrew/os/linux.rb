# typed: true
# frozen_string_literal: true

require "utils"

module OS
  # Helper module for querying system information on Linux.
  module Linux
    sig { returns(String) }
    def self.os_version
      if which("lsb_release")
        lsb_info = Utils.popen_read("lsb_release", "-a")
        description = lsb_info[/^Description:\s*(.*)$/, 1].force_encoding("UTF-8")
        codename = lsb_info[/^Codename:\s*(.*)$/, 1]
        if codename.blank? || (codename == "n/a")
          description
        else
          "#{description} (#{codename})"
        end
      elsif (redhat_release = Pathname.new("/etc/redhat-release")).readable?
        redhat_release.read.chomp
      elsif ::OS_VERSION.present?
        ::OS_VERSION
      else
        "Unknown"
      end
    end

    sig { returns(T::Boolean) }
    def self.wsl?
      /-microsoft/i.match?(OS.kernel_version.to_s)
    end

    sig { returns(Version) }
    def self.wsl_version
      return Version::NULL unless wsl?

      kernel = OS.kernel_version.to_s
      if Version.new(T.must(kernel[/^([0-9.]*)-.*/, 1])) > Version.new("5.15")
        Version.new("2 (Microsoft Store)")
      elsif kernel.include?("-microsoft")
        Version.new("2")
      elsif kernel.include?("-Microsoft")
        Version.new("1")
      else
        Version::NULL
      end
    end
  end

  # rubocop:disable Style/Documentation
  module Mac
    ::MacOS = OS::Mac

    raise "Loaded OS::Linux on generic OS!" if ENV["HOMEBREW_TEST_GENERIC_OS"]

    def self.version
      odeprecated "`MacOS.version` on Linux"
      MacOSVersion::NULL
    end

    def self.full_version
      odeprecated "`MacOS.full_version` on Linux"
      MacOSVersion::NULL
    end

    def self.languages
      odeprecated "`MacOS.languages` on Linux"
      @languages ||= Array(ENV["LANG"]&.slice(/[a-z]+/)).uniq
    end

    def self.language
      odeprecated "`MacOS.language` on Linux"
      languages.first
    end

    def self.sdk_root_needed?
      odeprecated "`MacOS.sdk_root_needed?` on Linux"
      false
    end

    def self.sdk_path_if_needed(_version = nil)
      odeprecated "`MacOS.sdk_path_if_needed` on Linux"
      nil
    end

    def self.sdk_path(_version = nil)
      odeprecated "`MacOS.sdk_path` on Linux"
      nil
    end

    module Xcode
      def self.version
        odeprecated "`MacOS::Xcode.version` on Linux"
        ::Version::NULL
      end

      def self.installed?
        odeprecated "`MacOS::Xcode.installed?` on Linux"
        false
      end
    end

    module CLT
      def self.version
        odeprecated "`MacOS::CLT.version` on Linux"
        ::Version::NULL
      end

      def self.installed?
        odeprecated "`MacOS::CLT.installed?` on Linux"
        false
      end
    end
  end
  # rubocop:enable Style/Documentation
end
