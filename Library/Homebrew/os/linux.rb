# typed: strict
# frozen_string_literal: true

require "utils"

module OS
  # Helper module for querying system information on Linux.
  module Linux
    raise "Loaded OS::Linux on generic OS!" if ENV["HOMEBREW_TEST_GENERIC_OS"]

    # This check is the only acceptable or necessary one in this file.
    # rubocop:disable Homebrew/MoveToExtendOS
    raise "Loaded OS::Linux on macOS!" if OS.mac?
    # rubocop:enable Homebrew/MoveToExtendOS

    @languages = T.let([], T::Array[String])

    # Get the OS version.
    #
    # @api internal
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

    sig { returns(T::Array[String]) }
    def self.languages
      return @languages if @languages.present?

      locale_variables = ENV.keys.grep(/^(?:LC_\S+|LANG|LANGUAGE)\Z/).sort
      ctl_ret = Utils.popen_read("localectl", "list-locales")
      if ctl_ret.present?
        list = ctl_ret.scan(/[^ \n"(),]+/)
      elsif locale_variables.present?
        keys = locale_variables.select { |var| ENV.fetch(var) }
        list = keys.map { |key| ENV.fetch(key) }
      else
        list = ["en_US.utf8"]
      end

      @languages = list.map { |item| item.split(".").first.tr("_", "-") }
    end

    sig { returns(T.nilable(String)) }
    def self.language
      languages.first
    end
  end
end
