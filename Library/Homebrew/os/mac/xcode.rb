# typed: false
# frozen_string_literal: true

module OS
  module Mac
    # Helper module for querying Xcode information.
    #
    # @api private
    module Xcode
      extend T::Sig

      module_function

      DEFAULT_BUNDLE_PATH = Pathname("/Applications/Xcode.app").freeze
      BUNDLE_ID = "com.apple.dt.Xcode"
      OLD_BUNDLE_ID = "com.apple.Xcode"

      # Bump these when a new version is available from the App Store and our
      # CI systems have been updated.
      # This may be a beta version for a beta macOS.
      sig { params(macos: MacOS::Version).returns(String) }
      def latest_version(macos: MacOS.version)
        latest_stable = "12.4"
        case macos
        when "11" then latest_stable
        when "10.15" then "12.4"
        when "10.14" then "11.3.1"
        when "10.13" then "10.1"
        when "10.12" then "9.2"
        when "10.11" then "8.2.1"
        when "10.10" then "7.2.1"
        when "10.9"  then "6.2"
        else
          raise "macOS '#{MacOS.version}' is invalid" unless OS::Mac.prerelease?

          # Default to newest known version of Xcode for unreleased macOS versions.
          latest_stable
        end
      end

      # Bump these if things are badly broken (e.g. no SDK for this macOS)
      # without this. Generally this will be the first Xcode release on that
      # macOS version (which may initially be a beta if that version of macOS is
      # also in beta).
      sig { returns(String) }
      def minimum_version
        case MacOS.version
        when "11" then "12.2"
        when "10.15" then "11.0"
        when "10.14" then "10.2"
        when "10.13" then "9.0"
        when "10.12" then "8.0"
        else "2.0"
        end
      end

      sig { returns(T::Boolean) }
      def below_minimum_version?
        return false unless installed?

        version < minimum_version
      end

      sig { returns(T::Boolean) }
      def latest_sdk_version?
        OS::Mac.full_version >= OS::Mac.latest_sdk_version
      end

      sig { returns(T::Boolean) }
      def needs_clt_installed?
        return false if latest_sdk_version?

        without_clt?
      end

      sig { returns(T::Boolean) }
      def outdated?
        return false unless installed?

        version < latest_version
      end

      sig { returns(T::Boolean) }
      def without_clt?
        !MacOS::CLT.installed?
      end

      # Returns a Pathname object corresponding to Xcode.app's Developer
      # directory or nil if Xcode.app is not installed.
      def prefix
        @prefix ||=
          begin
            dir = MacOS.active_developer_dir

            if dir.empty? || dir == CLT::PKG_PATH || !File.directory?(dir)
              path = bundle_path
              path/"Contents/Developer" if path
            else
              # Use cleanpath to avoid pathological trailing slash
              Pathname.new(dir).cleanpath
            end
          end
      end

      sig { returns(Pathname) }
      def toolchain_path
        Pathname("#{prefix}/Toolchains/XcodeDefault.xctoolchain")
      end

      def bundle_path
        # Use the default location if it exists.
        return DEFAULT_BUNDLE_PATH if DEFAULT_BUNDLE_PATH.exist?

        # Ask Spotlight where Xcode is. If the user didn't install the
        # helper tools and installed Xcode in a non-conventional place, this
        # is our only option. See: https://superuser.com/questions/390757
        MacOS.app_with_bundle_id(BUNDLE_ID, OLD_BUNDLE_ID)
      end

      sig { returns(T::Boolean) }
      def installed?
        !prefix.nil?
      end

      def sdk_locator
        @sdk_locator ||= XcodeSDKLocator.new
      end

      def sdk(v = nil)
        sdk_locator.sdk_if_applicable(v)
      end

      def sdk_path(v = nil)
        sdk(v)&.path
      end

      def installation_instructions
        if OS::Mac.prerelease?
          <<~EOS
            Xcode can be installed from:
              #{Formatter.url("https://developer.apple.com/download/more/")}
          EOS
        else
          <<~EOS
            Xcode can be installed from the App Store.
          EOS
        end
      end

      sig { returns(String) }
      def update_instructions
        if OS::Mac.prerelease?
          <<~EOS
            Xcode can be updated from:
              #{Formatter.url("https://developer.apple.com/download/more/")}
          EOS
        else
          <<~EOS
            Xcode can be updated from the App Store.
          EOS
        end
      end

      def version
        # may return a version string
        # that is guessed based on the compiler, so do not
        # use it in order to check if Xcode is installed.
        if @version ||= detect_version
          ::Version.new @version
        else
          ::Version::NULL
        end
      end

      def detect_version
        # This is a separate function as you can't cache the value out of a block
        # if return is used in the middle, which we do many times in here.
        return if !MacOS::Xcode.installed? && !MacOS::CLT.installed?

        %W[
          #{prefix}/usr/bin/xcodebuild
          #{which("xcodebuild")}
        ].uniq.each do |xcodebuild_path|
          next unless File.executable? xcodebuild_path

          xcodebuild_output = Utils.popen_read(xcodebuild_path, "-version")
          next unless $CHILD_STATUS.success?

          xcode_version = xcodebuild_output[/Xcode (\d+(\.\d+)*)/, 1]
          return xcode_version if xcode_version

          # Xcode 2.x's xcodebuild has a different version string
          case xcodebuild_output[/DevToolsCore-(\d+\.\d)/, 1]
          when "798.0" then return "2.5"
          when "515.0" then return "2.0"
          end
        end

        detect_version_from_clang_version
      end

      sig { returns(String) }
      def detect_version_from_clang_version
        return "dunno" if DevelopmentTools.clang_version.null?

        # This logic provides a fake Xcode version based on the
        # installed CLT version. This is useful as they are packaged
        # simultaneously so workarounds need to apply to both based on their
        # comparable version.
        case (DevelopmentTools.clang_version.to_f * 10).to_i
        when 0       then "dunno"
        when 60      then "6.0"
        when 61      then "6.1"
        when 70      then "7.0"
        when 73      then "7.3"
        when 80      then "8.0"
        when 81      then "8.3"
        when 90      then "9.2"
        when 91      then "9.4"
        when 100     then "10.3"
        when 110     then "11.5"
        else              "12.0"
        end
      end

      def default_prefix?
        prefix.to_s == "/Applications/Xcode.app/Contents/Developer"
      end
    end

    # Helper module for querying macOS Command Line Tools information.
    #
    # @api private
    module CLT
      extend T::Sig

      module_function

      # The original Mavericks CLT package ID
      EXECUTABLE_PKG_ID = "com.apple.pkg.CLTools_Executables"
      MAVERICKS_NEW_PKG_ID = "com.apple.pkg.CLTools_Base" # obsolete
      PKG_PATH = "/Library/Developer/CommandLineTools"

      # Returns true even if outdated tools are installed.
      sig { returns(T::Boolean) }
      def installed?
        !version.null?
      end

      def separate_header_package?
        version >= "10" && MacOS.version >= "10.14"
      end

      def provides_sdk?
        version >= "8"
      end

      def sdk_locator
        @sdk_locator ||= CLTSDKLocator.new
      end

      def sdk(v = nil)
        sdk_locator.sdk_if_applicable(v)
      end

      def sdk_path(v = nil)
        sdk(v)&.path
      end

      def installation_instructions
        if MacOS.version == "10.14"
          # This is not available from `xcode-select`
          <<~EOS
            Install the Command Line Tools for Xcode 11.3.1 from:
              #{Formatter.url("https://developer.apple.com/download/more/")}
          EOS
        else
          <<~EOS
            Install the Command Line Tools:
              xcode-select --install
          EOS
        end
      end

      sig { returns(String) }
      def update_instructions
        software_update_location = if MacOS.version >= "10.14"
          "System Preferences"
        else
          "the App Store"
        end

        <<~EOS
          Update them from Software Update in #{software_update_location} or run:
            softwareupdate --all --install --force

          If that doesn't show you any updates, run:
            sudo rm -rf /Library/Developer/CommandLineTools
            sudo xcode-select --install

          Alternatively, manually download them from:
            #{Formatter.url("https://developer.apple.com/download/more/")}.
        EOS
      end

      # Bump these when the new version is distributed through Software Update
      # and our CI systems have been updated.
      sig { returns(String) }
      def latest_clang_version
        case MacOS.version
        when "11", "10.15" then "1200.0.32.29"
        when "10.14" then "1100.0.33.17"
        when "10.13" then "1000.10.44.2"
        when "10.12" then "900.0.39.2"
        when "10.11" then "800.0.42.1"
        when "10.10" then "700.1.81"
        else              "600.0.57"
        end
      end

      # Bump these if things are badly broken (e.g. no SDK for this macOS)
      # without this. Generally this will be the first stable CLT release on
      # that macOS version.
      sig { returns(String) }
      def minimum_version
        case MacOS.version
        when "11" then "12.5.0"
        when "10.15" then "11.0.0"
        when "10.14" then "10.0.0"
        when "10.13" then "9.0.0"
        when "10.12" then "8.0.0"
        else              "1.0.0"
        end
      end

      def below_minimum_version?
        return false unless installed?

        version < minimum_version
      end

      sig { returns(T::Boolean) }
      def outdated?
        clang_version = detect_clang_version
        return false unless clang_version

        ::Version.new(clang_version) < latest_clang_version
      end

      def detect_clang_version
        version_output = Utils.popen_read("#{PKG_PATH}/usr/bin/clang", "--version")
        version_output[/clang-(\d+\.\d+\.\d+(\.\d+)?)/, 1]
      end

      def detect_version_from_clang_version
        detect_clang_version&.sub(/^(\d+)0(\d)\./, "\\1.\\2.")
      end

      # Version string (a pretty long one) of the CLT package.
      # Note that the different ways of installing the CLTs lead to different
      # version numbers.
      def version
        if @version ||= detect_version
          ::Version.new @version
        else
          ::Version::NULL
        end
      end

      def detect_version
        version = nil
        [EXECUTABLE_PKG_ID, MAVERICKS_NEW_PKG_ID].each do |id|
          next unless File.exist?("#{PKG_PATH}/usr/bin/clang")

          version = MacOS.pkgutil_info(id)[/version: (.+)$/, 1]
          return version if version
        end

        detect_version_from_clang_version
      end
    end
  end
end
