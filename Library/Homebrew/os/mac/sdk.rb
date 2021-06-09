# typed: true
# frozen_string_literal: true

require "os/mac/version"

module OS
  module Mac
    # Class representing a macOS SDK.
    #
    # @api private
    class SDK
      # 11.x SDKs are explicitly excluded - we want the MacOSX11.sdk symlink instead.
      VERSIONED_SDK_REGEX = /MacOSX(10\.\d+|\d+)\.sdk$/.freeze

      attr_reader :version, :path, :source

      def initialize(version, path, source)
        @version = version
        @path = Pathname.new(path)
        @source = source
      end
    end

    # Base class for SDK locators.
    #
    # @api private
    class BaseSDKLocator
      class NoSDKError < StandardError; end

      def sdk_for(v)
        sdk = all_sdks.find { |s| s.version == v }
        raise NoSDKError if sdk.nil?

        sdk
      end

      def all_sdks
        return @all_sdks if @all_sdks

        @all_sdks = []

        # Bail out if there is no SDK prefix at all
        return @all_sdks unless File.directory? sdk_prefix

        Dir["#{sdk_prefix}/MacOSX*.sdk"].each do |sdk_path|
          next unless sdk_path.match?(SDK::VERSIONED_SDK_REGEX)

          version = read_sdk_version(Pathname.new(sdk_path))
          next if version.nil?

          @all_sdks << SDK.new(version, sdk_path, source)
        end

        # Fall back onto unversioned SDK if we've not found a suitable SDK
        if @all_sdks.empty?
          sdk_path = Pathname.new("#{sdk_prefix}/MacOSX.sdk")
          if (version = read_sdk_version(sdk_path))
            @all_sdks << SDK.new(version, sdk_path, source)
          end
        end

        @all_sdks
      end

      def sdk_if_applicable(v = nil)
        sdk = begin
          if v.blank?
            sdk_for OS::Mac.version
          else
            sdk_for v
          end
        rescue NoSDKError
          latest_sdk
        end
        return if sdk.blank?

        # On OSs lower than 11, whenever the major versions don't match,
        # only return an SDK older than the OS version if it was specifically requested
        return if v.blank? && sdk.version < OS::Mac.version

        sdk
      end

      def source
        nil
      end

      private

      def sdk_prefix
        ""
      end

      def latest_sdk
        all_sdks.max_by(&:version)
      end

      def read_sdk_version(sdk_path)
        sdk_settings = sdk_path/"SDKSettings.json"
        sdk_settings_string = sdk_settings.read if sdk_settings.exist?

        # Pre-10.14 SDKs
        sdk_settings = sdk_path/"SDKSettings.plist"
        if sdk_settings_string.blank? && sdk_settings.exist?
          result = system_command("plutil", args: ["-convert", "json", "-o", "-", sdk_settings])
          sdk_settings_string = result.stdout if result.success?
        end

        return if sdk_settings_string.blank?

        sdk_settings_json = JSON.parse(sdk_settings_string)
        return if sdk_settings_json.blank?

        version_string = sdk_settings_json.fetch("Version", nil)
        return if version_string.blank?

        begin
          OS::Mac::Version.new(version_string).strip_patch
        rescue MacOSVersionError
          nil
        end
      end
    end
    private_constant :BaseSDKLocator

    # Helper class for locating the Xcode SDK.
    #
    # @api private
    class XcodeSDKLocator < BaseSDKLocator
      extend T::Sig

      sig { returns(Symbol) }
      def source
        :xcode
      end

      private

      def sdk_prefix
        @sdk_prefix ||= begin
          # Xcode.prefix is pretty smart, so let's look inside to find the sdk
          sdk_prefix = "#{Xcode.prefix}/Platforms/MacOSX.platform/Developer/SDKs"
          # Finally query Xcode itself (this is slow, so check it last)
          sdk_platform_path = Utils.popen_read(DevelopmentTools.locate("xcrun"), "--show-sdk-platform-path").chomp
          sdk_prefix = File.join(sdk_platform_path, "Developer", "SDKs") unless File.directory? sdk_prefix

          sdk_prefix
        end
      end
    end

    # Helper class for locating the macOS Command Line Tools SDK.
    #
    # @api private
    class CLTSDKLocator < BaseSDKLocator
      extend T::Sig

      sig { returns(Symbol) }
      def source
        :clt
      end

      private

      # While CLT SDKs existed prior to Xcode 10, those packages also
      # installed a traditional Unix-style header layout and we prefer
      # using that.
      # As of Xcode 10, the Unix-style headers are installed via a
      # separate package, so we can't rely on their being present.
      # This will only look up SDKs on Xcode 10 or newer, and still
      # return nil SDKs for Xcode 9 and older.
      def sdk_prefix
        @sdk_prefix ||= if CLT.provides_sdk?
          "#{CLT::PKG_PATH}/SDKs"
        else
          ""
        end
      end
    end
  end
end
