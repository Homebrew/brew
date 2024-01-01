# typed: true
# frozen_string_literal: true

require "macos_version"

require "os/mac/xcode"
require "os/mac/sdk"
require "os/mac/keg"

# TODO: remove this once the `MacOS` module is undefined on Linux
require "simulate_system"

module OS
  # Helper module for querying system information on macOS.
  module Mac
    ::MacOS = OS::Mac

    raise "Loaded OS::Mac on generic OS!" if ENV["HOMEBREW_TEST_GENERIC_OS"]

    VERSION = ENV.fetch("HOMEBREW_MACOS_VERSION").chomp.freeze
    private_constant :VERSION

    # This can be compared to numerics, strings, or symbols
    # using the standard Ruby Comparable methods.
    sig { returns(MacOSVersion) }
    def self.version
      odeprecated "`MacOS.version` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      @version ||= full_version.strip_patch
    end

    # This can be compared to numerics, strings, or symbols
    # using the standard Ruby Comparable methods.
    sig { returns(MacOSVersion) }
    def self.full_version
      odeprecated "`MacOS.full_version` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      @full_version ||= if ENV["HOMEBREW_FAKE_EL_CAPITAN"] # for Portable Ruby building
        MacOSVersion.new("10.11.6")
      else
        MacOSVersion.new(VERSION)
      end
    end

    sig { params(version: String).void }
    def self.full_version=(version)
      @full_version = MacOSVersion.new(version.chomp)
      @version = nil
    end

    sig { returns(::Version) }
    def self.latest_sdk_version
      # TODO: bump version when new Xcode macOS SDK is released
      # NOTE: We only track the major version of the SDK.
      ::Version.new("13")
    end

    sig { returns(String) }
    def self.preferred_perl_version
      if version >= :sonoma
        "5.34"
      elsif version >= :big_sur
        "5.30"
      else
        "5.18"
      end
    end

    def self.languages
      odeprecated "`MacOS.languages` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      return @languages if @languages

      os_langs = Utils.popen_read("defaults", "read", "-g", "AppleLanguages")
      if os_langs.blank?
        # User settings don't exist so check the system-wide one.
        os_langs = Utils.popen_read("defaults", "read", "/Library/Preferences/.GlobalPreferences", "AppleLanguages")
      end
      os_langs = os_langs.scan(/[^ \n"(),]+/)

      @languages = os_langs
    end

    def self.language
      odeprecated "`MacOS.language` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      languages.first
    end

    sig { returns(String) }
    def self.active_developer_dir
      @active_developer_dir ||= Utils.popen_read("/usr/bin/xcode-select", "-print-path").strip
    end

    sig { returns(T::Boolean) }
    def self.sdk_root_needed?
      odeprecated "`MacOS.sdk_root_needed?` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      if MacOS::CLT.installed?
        # If there's no CLT SDK, return false
        return false unless MacOS::CLT.provides_sdk?
        # If the CLT is installed and headers are provided by the system, return false
        return false unless MacOS::CLT.separate_header_package?
      end

      true
    end

    # If a specific SDK is requested:
    #
    #   1. The requested SDK is returned, if it's installed.
    #   2. If the requested SDK is not installed, the newest SDK (if any SDKs
    #      are available) is returned.
    #   3. If no SDKs are available, nil is returned.
    #
    # If no specific SDK is requested, the SDK matching the OS version is returned,
    # if available. Otherwise, the latest SDK is returned.

    def self.sdk_locator
      if CLT.installed? && CLT.provides_sdk?
        CLT.sdk_locator
      else
        Xcode.sdk_locator
      end
    end

    def self.sdk(version = nil)
      sdk_locator.sdk_if_applicable(version)
    end

    def self.sdk_for_formula(formula, version = nil, check_only_runtime_requirements: false)
      # If the formula requires Xcode, don't return the CLT SDK
      # If check_only_runtime_requirements is true, don't necessarily return the
      # Xcode SDK if the XcodeRequirement is only a build or test requirement.
      return Xcode.sdk if formula.requirements.any? do |req|
        next false unless req.is_a? XcodeRequirement
        next false if check_only_runtime_requirements && req.build? && !req.test?

        true
      end

      sdk(version)
    end

    # Returns the path to an SDK or nil, following the rules set by {sdk}.
    def self.sdk_path(version = nil)
      odeprecated "`MacOS.sdk_path` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      s = sdk(version)
      s&.path
    end

    def self.sdk_path_if_needed(version = nil)
      odeprecated "`MacOS.sdk_path_if_needed` on Linux" if Homebrew::SimulateSystem.simulating_or_running_on_linux?
      # Prefer CLT SDK when both Xcode and the CLT are installed.
      # Expected results:
      # 1. On Xcode-only systems, return the Xcode SDK.
      # 2. On Xcode-and-CLT systems where headers are provided by the system, return nil.
      # 3. On CLT-only systems with no CLT SDK, return nil.
      # 4. On CLT-only systems with a CLT SDK, where headers are provided by the system, return nil.
      # 5. On CLT-only systems with a CLT SDK, where headers are not provided by the system, return the CLT SDK.

      return unless sdk_root_needed?

      sdk_path(version)
    end

    # See these issues for some history:
    #
    # - {https://github.com/Homebrew/legacy-homebrew/issues/13}
    # - {https://github.com/Homebrew/legacy-homebrew/issues/41}
    # - {https://github.com/Homebrew/legacy-homebrew/issues/48}
    def self.macports_or_fink
      paths = []

      # First look in the path because MacPorts is relocatable and Fink
      # may become relocatable in the future.
      %w[port fink].each do |ponk|
        path = which(ponk)
        paths << path unless path.nil?
      end

      # Look in the standard locations, because even if port or fink are
      # not in the path they can still break builds if the build scripts
      # have these paths baked in.
      %w[/sw/bin/fink /opt/local/bin/port].each do |ponk|
        path = Pathname.new(ponk)
        paths << path if path.exist?
      end

      # Finally, some users make their MacPorts or Fink directories
      # read-only in order to try out Homebrew, but this doesn't work as
      # some build scripts error out when trying to read from these now
      # unreadable paths.
      %w[/sw /opt/local].map { |p| Pathname.new(p) }.each do |path|
        paths << path if path.exist? && !path.readable?
      end

      paths.uniq
    end

    sig { params(ids: String).returns(T.nilable(Pathname)) }
    def self.app_with_bundle_id(*ids)
      path = mdfind(*ids)
             .reject { |p| p.include?("/Backups.backupdb/") }
             .first
      Pathname.new(path) if path.present?
    end

    sig { params(ids: String).returns(T::Array[String]) }
    def self.mdfind(*ids)
      (@mdfind ||= {}).fetch(ids) do
        @mdfind[ids] = Utils.popen_read("/usr/bin/mdfind", mdfind_query(*ids)).split("\n")
      end
    end

    def self.pkgutil_info(id)
      (@pkginfo ||= {}).fetch(id) do |key|
        @pkginfo[key] = Utils.popen_read("/usr/sbin/pkgutil", "--pkg-info", key).strip
      end
    end

    sig { params(ids: String).returns(String) }
    def self.mdfind_query(*ids)
      ids.map! { |id| "kMDItemCFBundleIdentifier == #{id}" }.join(" || ")
    end
  end
end
