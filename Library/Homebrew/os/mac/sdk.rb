# typed: strict
# frozen_string_literal: true

require "system_command"

module OS
  module Mac
    # Class representing a macOS SDK.
    class SDK
      # 11.x SDKs are explicitly excluded - we want the MacOSX11.sdk symlink instead.
      VERSIONED_SDK_REGEX = /MacOSX(10\.\d+|\d+)\.sdk$/

      sig { returns(MacOSVersion) }
      attr_reader :version

      sig { returns(::Pathname) }
      attr_reader :path

      sig { returns(Symbol) }
      attr_reader :source

      sig { params(version: MacOSVersion, path: T.any(String, ::Pathname), source: Symbol).void }
      def initialize(version, path, source)
        @version = version
        @path = T.let(Pathname(path), ::Pathname)
        @source = source
      end
    end

    # Base class for SDK locators.
    class BaseSDKLocator
      extend T::Helpers
      include SystemCommand::Mixin

      abstract!

      class NoSDKError < StandardError; end

      sig { void }
      def initialize
        @all_sdks = T.let(nil, T.nilable(T::Array[SDK]))
        @sdk_prefix = T.let(nil, T.nilable(String))
      end

      sig { params(version: MacOSVersion).returns(SDK) }
      def sdk_for(version)
        sdk = all_sdks.find { |s| s.version == version }
        raise NoSDKError if sdk.nil?

        sdk
      end

      sig { returns(T::Array[SDK]) }
      def all_sdks
        return @all_sdks if @all_sdks

        @all_sdks = []

        # Bail out if there is no SDK prefix at all
        return @all_sdks unless File.directory? sdk_prefix

        found_versions = Set.new

        Dir["#{sdk_prefix}/MacOSX*.sdk"].each do |sdk_path|
          next unless sdk_path.match?(SDK::VERSIONED_SDK_REGEX)

          version = read_sdk_version(::Pathname.new(sdk_path))
          next if version.nil?

          @all_sdks << SDK.new(version, sdk_path, source)
          found_versions << version
        end

        # Use unversioned SDK only if we don't have one matching that version.
        sdk_path = ::Pathname.new("#{sdk_prefix}/MacOSX.sdk")
        if (version = read_sdk_version(sdk_path)) && found_versions.exclude?(version)
          @all_sdks << SDK.new(version, sdk_path, source)
        end

        @all_sdks
      end

      sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(SDK)) }
      def sdk_if_applicable(version = nil)
        sdk = begin
          if version.blank?
            sdk_for OS::Mac.version
          else
            sdk_for version
          end
        rescue NoSDKError
          latest_sdk
        end
        return if sdk.blank?

        # On OSs lower than 11, whenever the major versions don't match,
        # only return an SDK older than the OS version if it was specifically requested
        return if version.blank? && sdk.version < OS::Mac.version

        sdk
      end

      sig { abstract.returns(Symbol) }
      def source; end

      private

      sig { abstract.returns(String) }
      def sdk_prefix; end

      sig { returns(T.nilable(SDK)) }
      def latest_sdk
        all_sdks.max_by(&:version)
      end

      sig { params(sdk_path: ::Pathname).returns(T.nilable(MacOSVersion)) }
      def read_sdk_version(sdk_path)
        sdk_settings = sdk_path/"SDKSettings.json"
        sdk_settings_string = sdk_settings.read if sdk_settings.exist?

        return if sdk_settings_string.blank?

        sdk_settings_json = JSON.parse(sdk_settings_string)
        return if sdk_settings_json.blank?

        version_string = sdk_settings_json.fetch("Version", nil)
        return if version_string.blank?

        begin
          MacOSVersion.new(version_string).strip_patch
        rescue MacOSVersion::Error
          nil
        end
      end
    end
    private_constant :BaseSDKLocator

    # Helper class for locating the Xcode SDK.
    class XcodeSDKLocator < BaseSDKLocator
      sig { override.returns(Symbol) }
      def source
        :xcode
      end

      private

      sig { override.returns(String) }
      def sdk_prefix
        @sdk_prefix ||= begin
          # Xcode.prefix is pretty smart, so let's look inside to find the sdk
          sdk_prefix = "#{Xcode.prefix}/Platforms/MacOSX.platform/Developer/SDKs"

          # Finally query Xcode itself (this is slow, so check it last)
          if !File.directory?(sdk_prefix) && (xcrun = ::DevelopmentTools.locate("xcrun"))
            sdk_platform_path = Utils.popen_read(xcrun, "--show-sdk-platform-path").chomp
            sdk_prefix = File.join(sdk_platform_path, "Developer", "SDKs")
          end

          sdk_prefix
        end
      end
    end

    # Helper class for locating the macOS Command Line Tools SDK.
    class CLTSDKLocator < BaseSDKLocator
      sig { override.returns(Symbol) }
      def source
        :clt
      end

      private

      # As of Xcode 10, the Unix-style headers are installed via a
      # separate package, so we can't rely on their being present.
      sig { override.returns(String) }
      def sdk_prefix
        @sdk_prefix ||= "#{CLT::PKG_PATH}/SDKs"
      end
    end
  end
end
