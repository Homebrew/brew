# typed: strict
# frozen_string_literal: true

require "macos_version"

require "os/mac/xcode"
require "os/mac/sdk"

module OS
  # Helper module for querying system information on macOS.
  module Mac
    extend Utils::Output::Mixin

    raise "Loaded OS::Mac on generic OS!" if ENV["HOMEBREW_TEST_GENERIC_OS"]

    # This check is the only acceptable or necessary one in this file.
    # rubocop:disable Homebrew/MoveToExtendOS
    raise "Loaded OS::Mac on Linux!" if OS.linux?
    # rubocop:enable Homebrew/MoveToExtendOS

    # Provide MacOS alias for backwards compatibility and nicer APIs.
    ::MacOS = OS::Mac

    VERSION = T.let(ENV.fetch("HOMEBREW_MACOS_VERSION").chomp.freeze, String)
    private_constant :VERSION

    # This can be compared to numerics, strings, or symbols
    # using the standard Ruby Comparable methods.
    #
    # @api internal
    sig { returns(MacOSVersion) }
    def self.version
      @version ||= T.let(full_version.strip_patch, T.nilable(MacOSVersion))
    end

    # This can be compared to numerics, strings, or symbols
    # using the standard Ruby Comparable methods.
    #
    # @api internal
    sig { returns(MacOSVersion) }
    def self.full_version
      @full_version ||= T.let(nil, T.nilable(MacOSVersion))
      # HOMEBREW_FAKE_MACOS is set system-wide in the macOS 11-arm64-cross image
      # for building a macOS 11 Portable Ruby on macOS 12
      # odisabled: remove support for Big Sur September (or later) 2027
      @full_version ||= if (fake_macos = ENV.fetch("HOMEBREW_FAKE_MACOS", nil))
        MacOSVersion.new(fake_macos)
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
      ::Version.new("26")
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

    sig { returns(T::Array[String]) }
    def self.languages
      @languages ||= T.let(nil, T.nilable(T::Array[String]))
      return @languages if @languages

      os_langs = Utils.popen_read("defaults", "read", "-g", "AppleLanguages")
      if os_langs.blank?
        # User settings don't exist so check the system-wide one.
        os_langs = Utils.popen_read("defaults", "read", "/Library/Preferences/.GlobalPreferences", "AppleLanguages")
      end
      os_langs = T.cast(os_langs.scan(/[^ \n"(),]+/), T::Array[String])

      @languages = os_langs
    end

    sig { returns(T.nilable(String)) }
    def self.language
      languages.first
    end

    sig { returns(String) }
    def self.active_developer_dir
      @active_developer_dir ||= T.let(
        Utils.popen_read("/usr/bin/xcode-select", "-print-path").strip,
        T.nilable(String),
      )
    end

    sig { returns(T::Boolean) }
    def self.sdk_root_needed?
      odeprecated "OS::Mac.sdk_root_needed?"
      true
    end

    sig { returns(T.any(CLTSDKLocator, XcodeSDKLocator)) }
    def self.sdk_locator
      if CLT.installed?
        CLT.sdk_locator
      else
        Xcode.sdk_locator
      end
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
    sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(SDK)) }
    def self.sdk(version = nil)
      sdk_locator.sdk_if_applicable(version)
    end

    # Returns the path to the SDK needed based on the formula's requirements.
    #
    # @api public
    sig {
      params(
        formula:                         Formula,
        version:                         T.nilable(MacOSVersion),
        check_only_runtime_requirements: T::Boolean,
      ).returns(T.nilable(SDK))
    }
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
    #
    # @api public
    sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(::Pathname)) }
    def self.sdk_path(version = nil)
      s = sdk(version)
      s&.path
    end

    # Prefer CLT SDK when both Xcode and the CLT are installed.
    # Expected results:
    # 1. On Xcode-only systems, return the Xcode SDK.
    # 2. On CLT-only systems, return the CLT SDK.
    #
    # @api public
    sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(::Pathname)) }
    def self.sdk_path_if_needed(version = nil)
      sdk_path(version)
    end

    # See these issues for some history:
    #
    # - {https://github.com/Homebrew/legacy-homebrew/issues/13}
    # - {https://github.com/Homebrew/legacy-homebrew/issues/41}
    # - {https://github.com/Homebrew/legacy-homebrew/issues/48}
    sig { returns(T::Array[Pathname]) }
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
        path = ::Pathname.new(ponk)
        paths << path if path.exist?
      end

      # Finally, some users make their MacPorts or Fink directories
      # read-only in order to try out Homebrew, but this doesn't work as
      # some build scripts error out when trying to read from these now
      # unreadable paths.
      %w[/sw /opt/local].map { |p| ::Pathname.new(p) }.each do |path|
        paths << path if path.exist? && !path.readable?
      end

      paths.uniq
    end

    sig { params(ids: String).returns(T.nilable(::Pathname)) }
    def self.app_with_bundle_id(*ids)
      require "bundle_version"

      paths = mdfind(*ids).filter_map do |bundle_path|
        ::Pathname.new(bundle_path) if bundle_path.exclude?("/Backups.backupdb/")
      end
      return paths.first unless paths.all? { |bp| (bp/"Contents/Info.plist").exist? }

      # Prefer newest one, if we can find it.
      paths.max_by { |bundle_path| Homebrew::BundleVersion.from_info_plist(bundle_path/"Contents/Info.plist") }
    end

    sig { params(ids: String).returns(T::Array[String]) }
    def self.mdfind(*ids)
      @mdfind ||= T.let(nil, T.nilable(T::Hash[T::Array[String], T::Array[String]]))
      (@mdfind ||= {}).fetch(ids) do
        @mdfind[ids] = Utils.popen_read("/usr/bin/mdfind", mdfind_query(*ids)).split("\n")
      end
    end

    sig { params(id: String).returns(String) }
    def self.pkgutil_info(id)
      @pkginfo ||= T.let(nil, T.nilable(T::Hash[String, String]))
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
