# typed: strict
# frozen_string_literal: true

require "utils/output"

module OS
  module Mac
    # Helper module for querying Xcode information.
    module Xcode
      DEFAULT_BUNDLE_PATH = ::Pathname.new("/Applications/Xcode.app").freeze
      BUNDLE_ID = "com.apple.dt.Xcode"
      OLD_BUNDLE_ID = "com.apple.Xcode"
      APPLE_DEVELOPER_DOWNLOAD_URL = "https://developer.apple.com/download/all/"

      # Bump these when a new version is available from the App Store and our
      # CI systems have been updated.
      # This may be a beta version for a beta macOS.
      # Pass both `macos` and `arm64` when querying a different system.
      sig { params(macos: MacOSVersion, arm64: T::Boolean).returns(String) }
      def self.latest_version(macos: MacOS.version, arm64: ::Hardware::CPU.physical_cpu_arm64?)
        macos = macos.strip_patch
        case macos
        when "27" then "27.0"
        when "26" then arm64 ? "27.0" : "26.6"
        when "15" then "26.3"
        when "14" then "16.2"
        when "13" then "15.2"
        when "12" then "14.2"
        when "11" then "13.2.1"
        else
          raise "macOS '#{macos}' is invalid" unless macos.prerelease?

          # Assume matching yearly Xcode release
          "#{macos}.0"
        end
      end

      # Bump these if things are badly broken (e.g. no SDK for this macOS)
      # without this. Generally this will be the first Xcode release on that
      # macOS version (which may initially be a beta if that version of macOS is
      # also in beta).
      sig { returns(String) }
      def self.minimum_version
        macos = MacOS.version
        case macos
        when "15" then "16.0"
        when "14" then "15.0"
        when "13" then "14.1"
        when "12" then "13.1"
        when "11" then "12.2"
        else
          "#{macos}.0"
        end
      end

      sig { returns(T::Boolean) }
      def self.below_minimum_version?
        return false unless installed?

        version < minimum_version
      end

      sig { returns(T::Boolean) }
      def self.latest_sdk_version?
        OS::Mac.full_version >= OS::Mac.latest_sdk_version
      end

      sig { returns(T::Boolean) }
      def self.needs_clt_installed?
        return false if latest_sdk_version?

        without_clt?
      end

      sig { returns(T::Boolean) }
      def self.outdated?
        return false unless installed?

        version < latest_version
      end

      sig { returns(T::Boolean) }
      def self.without_clt?
        !MacOS::CLT.installed?
      end

      # Returns a Pathname object corresponding to Xcode.app's Developer
      # directory or nil if Xcode.app is not installed.
      sig { returns(T.nilable(::Pathname)) }
      def self.prefix
        @prefix ||= T.let(begin
          dir = MacOS.active_developer_dir

          if dir.empty? || dir == CLT::PKG_PATH || !File.directory?(dir)
            path = bundle_path
            path/"Contents/Developer" if path
          else
            # Use cleanpath to avoid pathological trailing slash
            ::Pathname.new(dir).cleanpath
          end
        end, T.nilable(::Pathname))
      end

      sig { returns(::Pathname) }
      def self.toolchain_path
        Pathname("#{prefix}/Toolchains/XcodeDefault.xctoolchain")
      end

      sig { returns(T.nilable(::Pathname)) }
      def self.bundle_path
        # Use the default location if it exists.
        return DEFAULT_BUNDLE_PATH if DEFAULT_BUNDLE_PATH.exist?

        # Ask Spotlight where Xcode is. If the user didn't install the
        # helper tools and installed Xcode in a non-conventional place, this
        # is our only option. See: https://superuser.com/questions/390757
        MacOS.app_with_bundle_id(BUNDLE_ID, OLD_BUNDLE_ID)
      end

      sig { returns(T::Boolean) }
      def self.installed?
        !prefix.nil?
      end

      sig { returns(XcodeSDKLocator) }
      def self.sdk_locator
        @sdk_locator ||= T.let(XcodeSDKLocator.new, T.nilable(OS::Mac::XcodeSDKLocator))
      end

      sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(SDK)) }
      def self.sdk(version = nil)
        sdk_locator.sdk_if_applicable(version)
      end

      sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(::Pathname)) }
      def self.sdk_path(version = nil)
        sdk(version)&.path
      end

      sig { returns(String) }
      def self.installation_instructions
        if OS::Mac.version.prerelease?
          <<~EOS
            Xcode can be installed from:
              #{Formatter.url(APPLE_DEVELOPER_DOWNLOAD_URL)}
          EOS
        else
          <<~EOS
            Xcode can be installed from the App Store.
          EOS
        end
      end

      sig { returns(String) }
      def self.update_instructions
        if OS::Mac.version.prerelease?
          <<~EOS
            Xcode can be updated from:
              #{Formatter.url(APPLE_DEVELOPER_DOWNLOAD_URL)}
          EOS
        else
          <<~EOS
            Xcode can be updated from the App Store.
          EOS
        end
      end

      # Get the Xcode version.
      #
      # @api internal
      sig { returns(::Version) }
      def self.version
        if @version ||= T.let(detect_version, T.nilable(String))
          ::Version.new @version
        else
          ::Version::NULL
        end
      end

      sig { returns(T.nilable(String)) }
      def self.detect_version
        # This is a separate function as you can't cache the value out of a block
        # if return is used in the middle, which we do many times in here.
        if (xcode_prefix = prefix)
          # Fast path that will probably almost always work unless `xcode-select -p` is misconfigured
          version_plist = xcode_prefix.parent/"version.plist"
          if version_plist.file?
            require "plist"
            data = Plist.parse_xml(version_plist, marshal: false)
            version = data["CFBundleShortVersionString"] if data
            return version if version
          end

          %W[
            #{prefix}/usr/bin/xcodebuild
            #{which("xcodebuild")}
          ].uniq.each do |xcodebuild_path|
            next unless File.executable? xcodebuild_path

            xcodebuild_output = Utils.popen_read(xcodebuild_path, "-version")
            next unless $CHILD_STATUS.success?

            xcode_version = xcodebuild_output[/Xcode (\d+(?:\.\d+)*)/, 1]
            return xcode_version if xcode_version
          end
        end

        nil
      end

      sig { returns(T::Boolean) }
      def self.default_prefix?
        prefix.to_s == "/Applications/Xcode.app/Contents/Developer"
      end
    end

    # Helper module for querying macOS Command Line Tools information.
    module CLT
      extend Utils::Output::Mixin

      EXECUTABLE_PKG_ID = "com.apple.pkg.CLTools_Executables"
      PKG_PATH = "/Library/Developer/CommandLineTools"

      # Returns true even if outdated tools are installed.
      sig { returns(T::Boolean) }
      def self.installed?
        File.exist?("#{PKG_PATH}/usr/bin/clang")
      end

      sig { returns(CLTSDKLocator) }
      def self.sdk_locator
        @sdk_locator ||= T.let(CLTSDKLocator.new, T.nilable(OS::Mac::CLTSDKLocator))
      end

      sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(SDK)) }
      def self.sdk(version = nil)
        sdk_locator.sdk_if_applicable(version)
      end

      sig { params(version: T.nilable(MacOSVersion)).returns(T.nilable(::Pathname)) }
      def self.sdk_path(version = nil)
        sdk(version)&.path
      end

      sig { returns(String) }
      def self.installation_instructions
        if OS::Mac.version.prerelease?
          <<~EOS
            Install the Command Line Tools for Xcode #{minimum_version.split(".").first} from:
              #{Formatter.url(MacOS::Xcode::APPLE_DEVELOPER_DOWNLOAD_URL)}
          EOS
        else
          <<~EOS
            Install the Command Line Tools:
              xcode-select --install
          EOS
        end
      end

      sig { params(reason: String).returns(String) }
      def self.reinstall_instructions(reason: "resolve your issues")
        <<~EOS
          If that doesn't #{reason}, run:
            sudo rm -rf /Library/Developer/CommandLineTools
            sudo xcode-select --install

          Alternatively, manually download them from:
            #{Formatter.url(MacOS::Xcode::APPLE_DEVELOPER_DOWNLOAD_URL)}.
          You should download the Command Line Tools for Xcode #{latest_version}.
        EOS
      end

      sig { returns(String) }
      def self.update_instructions
        software_update_location = if MacOS.version >= "13"
          "System Settings"
        else
          "System Preferences"
        end

        <<~EOS
          Update them from Software Update in #{software_update_location}.

          #{reinstall_instructions(reason: "show you any updates")}
        EOS
      end

      sig { returns(String) }
      def self.installation_then_reinstall_instructions
        <<~EOS
          #{installation_instructions}
          #{reinstall_instructions}
        EOS
      end

      # Bump these when the new version is distributed through Software Update
      # and our CI systems have been updated.
      #
      # CLT releases can differ from Xcode, so override mismatches and
      # share Xcode's latest version otherwise.
      sig { returns(String) }
      def self.latest_version
        case MacOS.version
        when "13" then "15.1"
        when "11" then "13.2"
        else           MacOS::Xcode.latest_version
        end
      end

      sig { params(macos: MacOSVersion, arm64: T::Boolean).returns(String) }
      def self.latest_clang_version(macos: MacOS.version, arm64: ::Hardware::CPU.physical_cpu_arm64?)
        case macos.strip_patch
        when "27" then "2100.3.34.2"
        when "26" then arm64 ? "2100.3.34.2" : "2100.1.1.101"
        when "15" then "1700.6.4.2"
        when "14" then "1600.0.26.6"
        when "13" then "1500.1.0.2.5"
        when "12" then "1400.0.29.202"
        else           "1300.0.29.30"
        end
      end

      # Bump these if things are badly broken (e.g. no SDK for this macOS)
      # without this. Generally this will be the first stable CLT release on
      # that macOS version.
      sig { returns(String) }
      def self.minimum_version
        macos = MacOS.version
        case macos
        when "15" then "16.0.0"
        when "14" then "15.0.0"
        when "13" then "14.0.0"
        when "12" then "13.0.0"
        when "11" then "12.5.0"
        else
          "#{macos}.0.0"
        end
      end

      sig { returns(T::Boolean) }
      def self.below_minimum_version?
        return false if version.null?

        version < minimum_version
      end

      sig { returns(T::Boolean) }
      def self.outdated?
        clang_version = detect_clang_version
        return false unless clang_version
        return false if !version.null? && version.major_minor_patch > latest_version

        ::Version.new(clang_version) < latest_clang_version
      end

      sig { returns(T.nilable(String)) }
      def self.detect_clang_version
        version_output = Utils.popen_read("#{PKG_PATH}/usr/bin/clang", "--version")
        version_output[/clang-(\d+(?:\.\d+)+)/, 1]
      end

      # Version string (a pretty long one) of the CLT package.
      # Note that the different ways of installing the CLTs lead to different
      # version numbers. Installations without a package receipt have an
      # unknown version (`Version::NULL`).
      #
      # @api internal
      sig { returns(::Version) }
      def self.version
        if @version ||= T.let(detect_version, T.nilable(String))
          ::Version.new @version
        else
          ::Version::NULL
        end
      end

      sig { returns(T.nilable(String)) }
      def self.detect_version
        return unless installed?

        MacOS.pkgutil_info(EXECUTABLE_PKG_ID)[/version: (.+)$/, 1]
      end
    end
  end
end
