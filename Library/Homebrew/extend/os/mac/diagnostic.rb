# typed: strict
# frozen_string_literal: true

require "extend/os/mac/pkgconf"

module OS
  module Mac
    module Diagnostic
      class Volumes
        sig { void }
        def initialize
          @volumes = T.let(get_mounts, T::Array[String])
        end

        sig { params(path: T.nilable(::Pathname)).returns(Integer) }
        def index_of(path)
          vols = get_mounts path

          # no volume found
          return -1 if vols.empty?

          vol_index = @volumes.index(vols[0])
          # volume not found in volume list
          return -1 if vol_index.nil?

          vol_index
        end

        sig { params(path: T.nilable(::Pathname)).returns(T::Array[String]) }
        def get_mounts(path = nil)
          vols = []
          # get the volume of path, if path is nil returns all volumes

          args = %w[/bin/df -P]
          args << path.to_s if path

          Utils.popen_read(*args) do |io|
            io.each_line do |line|
              case line.chomp
                # regex matches: /dev/disk0s2   489562928 440803616  48247312    91%    /
              when /^.+\s+[0-9]+\s+[0-9]+\s+[0-9]+\s+[0-9]{1,3}%\s+(.+)/
                vols << Regexp.last_match(1)
              end
            end
          end
          vols
        end
      end

      module Checks
        extend T::Helpers

        requires_ancestor { Homebrew::Diagnostic::Checks }

        sig { params(verbose: T::Boolean).void }
        def initialize(verbose: true)
          super
          @found = T.let([], T::Array[String])
        end

        sig { returns(T::Array[String]) }
        def fatal_preinstall_checks
          checks = %w[
            check_access_directories
          ]

          # We need the developer tools for `codesign`.
          checks << "check_for_installed_developer_tools" if ::Hardware::CPU.arm?

          checks.freeze
        end

        sig { returns(T::Array[String]) }
        def fatal_build_from_source_checks
          %w[
            check_xcode_license_approved
            check_xcode_minimum_version
            check_clt_minimum_version
            check_if_xcode_needs_clt_installed
            check_if_supported_sdk_available
            check_broken_sdks
          ].freeze
        end

        sig { returns(T::Array[String]) }
        def fatal_setup_build_environment_checks
          %w[
            check_xcode_minimum_version
            check_clt_minimum_version
            check_if_supported_sdk_available
          ].freeze
        end

        sig { returns(T::Array[String]) }
        def supported_configuration_checks
          %w[
            check_for_unsupported_macos
          ].freeze
        end

        sig { returns(T::Array[String]) }
        def build_from_source_checks
          %w[
            check_for_installed_developer_tools
            check_xcode_up_to_date
            check_clt_up_to_date
          ].freeze
        end

        sig { returns(T.nilable(String)) }
        def check_for_non_prefixed_findutils
          findutils = ::Formula["findutils"]
          return unless findutils.any_version_installed?

          gnubin = %W[#{findutils.opt_libexec}/gnubin #{findutils.libexec}/gnubin]
          default_names = Tab.for_name("findutils").with? "default-names"
          return if !default_names && !paths.intersect?(gnubin)

          <<~EOS
            Putting non-prefixed findutils in your path can cause python builds to fail.
          EOS
        rescue FormulaUnavailableError
          nil
        end

        sig { returns(T.nilable(String)) }
        def check_for_unsupported_macos
          return if Homebrew::EnvConfig.developer?
          return if ENV["HOMEBREW_INTEGRATION_TEST"]

          tier = 2
          who = +"We"
          what = if OS::Mac.version.prerelease?
            "pre-release version."
          elsif OS::Mac.version.outdated_release?
            tier = 3
            who << " (and Apple)"
            <<~EOS.chomp
              old version.
              You may have better luck with MacPorts which supports older versions of macOS:
                #{Formatter.url("https://www.macports.org")}
            EOS
          end
          return if what.blank?

          who.freeze

          <<~EOS
            You are using macOS #{MacOS.version}.
            #{who} do not provide support for this #{what}

            #{support_tier_message(tier:)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_for_opencore
          return if ::Hardware::CPU.physical_cpu_arm64?

          # https://dortania.github.io/OpenCore-Legacy-Patcher/UPDATE.html#checking-oclp-and-opencore-versions
          begin
            opencore_version = Utils.safe_popen_read("/usr/sbin/nvram",
                                                     "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version").split[1]
            oclp_version = Utils.safe_popen_read("/usr/sbin/nvram",
                                                 "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:OCLP-Version").split[1]
            return if opencore_version.blank? || oclp_version.blank?
          rescue ErrorDuringExecution
            return
          end

          oclp_support_tier = ::Hardware::CPU.features.include?(:pclmulqdq) ? 2 : 3

          <<~EOS
            You have booted macOS using OpenCore Legacy Patcher.
            We do not provide support for this configuration.

            #{support_tier_message(tier: oclp_support_tier)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_up_to_date
          return unless MacOS::Xcode.outdated?

          # avoid duplicate very similar messages
          return if MacOS::Xcode.below_minimum_version?

          # CI images are going to end up outdated so don't complain when
          # `brew test-bot` runs `brew doctor` in the CI for the Homebrew/brew
          # repository. This only needs to support whatever CI providers
          # Homebrew/brew is currently using.
          return if GitHub::Actions.env_set?

          message = <<~EOS
            Your Xcode (#{MacOS::Xcode.version}) is outdated.
            Please update to Xcode #{MacOS::Xcode.latest_version} (or delete it).
            #{MacOS::Xcode.update_instructions}

            #{support_tier_message(tier: 2)}
          EOS

          if OS::Mac.version.prerelease?
            current_path = Utils.popen_read("/usr/bin/xcode-select", "-p")
            message += <<~EOS
              If #{MacOS::Xcode.latest_version} is installed, you may need to:
                sudo xcode-select --switch /Applications/Xcode.app
              Current developer directory is:
                #{current_path}
            EOS
          end
          message
        end

        sig { returns(T.nilable(String)) }
        def check_clt_up_to_date
          return unless MacOS::CLT.outdated?

          # avoid duplicate very similar messages
          return if MacOS::CLT.below_minimum_version?

          # CI images are going to end up outdated so don't complain when
          # `brew test-bot` runs `brew doctor` in the CI for the Homebrew/brew
          # repository. This only needs to support whatever CI providers
          # Homebrew/brew is currently using.
          return if GitHub::Actions.env_set?

          <<~EOS
            A newer Command Line Tools release is available.
            #{MacOS::CLT.update_instructions}

            #{support_tier_message(tier: 2)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_minimum_version
          return unless MacOS::Xcode.below_minimum_version?

          xcode = MacOS::Xcode.version.to_s
          xcode += " => #{MacOS::Xcode.prefix}" unless MacOS::Xcode.default_prefix?

          <<~EOS
            Your Xcode (#{xcode}) at #{MacOS::Xcode.bundle_path} is too outdated.
            Please update to Xcode #{MacOS::Xcode.latest_version} (or delete it).
            #{MacOS::Xcode.update_instructions}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_clt_minimum_version
          return unless MacOS::CLT.below_minimum_version?

          <<~EOS
            Your Command Line Tools are too outdated.
            #{MacOS::CLT.update_instructions}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_if_xcode_needs_clt_installed
          return unless MacOS::Xcode.needs_clt_installed?

          <<~EOS
            Xcode alone is not sufficient on #{MacOS.version.pretty_name}.
            #{::DevelopmentTools.installation_instructions}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_prefix
          prefix = MacOS::Xcode.prefix
          return if prefix.nil?
          return unless prefix.to_s.include?(" ")

          <<~EOS
            Xcode is installed to a directory with a space in the name.
            This will cause some formulae to fail to build.
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_prefix_exists
          prefix = MacOS::Xcode.prefix
          return if prefix.nil? || prefix.exist?

          <<~EOS
            The directory Xcode is reportedly installed to doesn't exist:
              #{prefix}
            You may need to `xcode-select` the proper path if you have moved Xcode.
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_select_path
          return if MacOS::CLT.installed?
          return unless MacOS::Xcode.installed?
          return if File.file?("#{MacOS.active_developer_dir}/usr/bin/xcodebuild")

          path = MacOS::Xcode.bundle_path
          path = "/Developer" if path.nil? || !path.directory?
          <<~EOS
            Your Xcode is configured with an invalid path.
            You should change it to the correct path:
              sudo xcode-select --switch #{path}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_xcode_license_approved
          # If the user installs Xcode-only, they have to approve the
          # license or no "xc*" tool will work.
          return unless `/usr/bin/xcrun clang 2>&1`.include?("license")
          return if $CHILD_STATUS.success?

          <<~EOS
            You have not agreed to the Xcode license.
            Agree to the license by opening Xcode.app or running:
              sudo xcodebuild -license
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_filesystem_case_sensitive
          dirs_to_check = [
            HOMEBREW_PREFIX,
            HOMEBREW_REPOSITORY,
            HOMEBREW_CELLAR,
            HOMEBREW_TEMP,
          ]
          case_sensitive_dirs = dirs_to_check.select do |dir|
            # We select the dir as being case-sensitive if either the UPCASED or the
            # downcased variant is missing.
            # Of course, on a case-insensitive fs, both exist because the os reports so.
            # In the rare situation when the user has indeed a downcased and an upcased
            # dir (e.g. /TMP and /tmp) this check falsely thinks it is case-insensitive
            # but we don't care because: 1. there is more than one dir checked, 2. the
            # check is not vital and 3. we would have to touch files otherwise.
            upcased = ::Pathname.new(dir.to_s.upcase)
            downcased = ::Pathname.new(dir.to_s.downcase)
            dir.exist? && !(upcased.exist? && downcased.exist?)
          end
          return if case_sensitive_dirs.empty?

          volumes = Volumes.new
          case_sensitive_vols = case_sensitive_dirs.map do |case_sensitive_dir|
            volumes.get_mounts(case_sensitive_dir)
          end
          case_sensitive_vols.uniq!

          <<~EOS
            The filesystem on #{case_sensitive_vols.join(",")} appears to be case-sensitive.
            The default macOS filesystem is case-insensitive. Please report any apparent problems.
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_for_gettext
          find_relative_paths("lib/libgettextlib.dylib",
                              "lib/libintl.dylib",
                              "include/libintl.h")
          return if @found.empty?

          # Our gettext formula will be caught by check_linked_keg_only_brews
          gettext = begin
            Formulary.factory("gettext")
          rescue
            nil
          end

          if gettext&.linked_keg&.directory?
            allowlist = ["#{HOMEBREW_CELLAR}/gettext"]
            if ::Hardware::CPU.physical_cpu_arm64?
              allowlist += %W[
                #{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}/Cellar/gettext
                #{HOMEBREW_DEFAULT_PREFIX}/Cellar/gettext
              ]
            end

            return if @found.all? do |path|
              realpath = ::Pathname.new(path).realpath.to_s
              realpath.start_with?(*allowlist)
            end
          end

          inject_file_list @found, <<~EOS
            gettext files detected at a system prefix.
            These files can cause compilation and link failures, especially if they
            are compiled with improper architectures. Consider removing these files:
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_for_iconv
          find_relative_paths("lib/libiconv.dylib", "include/iconv.h")
          return if @found.empty?

          libiconv = begin
            Formulary.factory("libiconv")
          rescue
            nil
          end
          if libiconv&.linked_keg&.directory?
            unless libiconv&.keg_only?
              <<~EOS
                A libiconv formula is installed and linked.
                This will break stuff. For serious. Unlink it.
              EOS
            end
          else
            inject_file_list @found, <<~EOS
              libiconv files detected at a system prefix other than /usr.
              Homebrew doesn't provide a libiconv formula and expects to link against
              the system version in /usr. libiconv in other prefixes can cause
              compile or link failure, especially if compiled with improper
              architectures. macOS itself never installs anything to /usr/local so
              it was either installed by a user or some other third party software.

              tl;dr: delete these files:
            EOS
          end
        end

        sig { returns(T.nilable(String)) }
        def check_for_multiple_volumes
          return unless HOMEBREW_CELLAR.exist?

          volumes = Volumes.new

          # Find the volumes for the TMP folder & HOMEBREW_CELLAR
          real_cellar = HOMEBREW_CELLAR.realpath
          where_cellar = volumes.index_of real_cellar

          begin
            tmp = ::Pathname.new(Dir.mktmpdir("doctor", HOMEBREW_TEMP))
            begin
              real_tmp = tmp.realpath.parent
              where_tmp = volumes.index_of real_tmp
            ensure
              Dir.delete tmp.to_s
            end
          rescue
            return
          end

          return if where_cellar == where_tmp

          <<~EOS
            Your Cellar and TEMP directories are on different volumes.
            macOS won't move relative symlinks across volumes unless the target file already
            exists. Formulae known to be affected by this are Git and Narwhal.

            You should set the `$HOMEBREW_TEMP` environment variable to a suitable
            directory on the same volume as your Cellar.

            #{support_tier_message(tier: 2)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_if_supported_sdk_available
          return unless ::DevelopmentTools.installed?
          return if MacOS.sdk

          locator = MacOS.sdk_locator

          source = if locator.source == :clt
            return if MacOS::CLT.below_minimum_version? # Handled by other diagnostics.

            update_instructions = MacOS::CLT.update_instructions
            "Command Line Tools (CLT)"
          else
            return if MacOS::Xcode.below_minimum_version? # Handled by other diagnostics.

            update_instructions = MacOS::Xcode.update_instructions
            "Xcode"
          end

          <<~EOS
            Your #{source} does not support macOS #{MacOS.version}.
            It is either outdated or was modified.
            Please update your #{source} or delete it if no updates are available.
            #{update_instructions}
          EOS
        end

        # The CLT 10.x -> 11.x upgrade process on 10.14 contained a bug which broke the SDKs.
        # Notably, MacOSX10.14.sdk would indirectly symlink to MacOSX10.15.sdk.
        # This diagnostic was introduced to check for this and recommend a full reinstall.
        sig { returns(T.nilable(String)) }
        def check_broken_sdks
          locator = MacOS.sdk_locator

          return if locator.all_sdks.all? do |sdk|
            path_version = sdk.path.basename.to_s[MacOS::SDK::VERSIONED_SDK_REGEX, 1]
            next true if path_version.blank?

            sdk.version == MacOSVersion.new(path_version).strip_patch
          end

          if locator.source == :clt
            source = "Command Line Tools (CLT)"
            path_to_remove = MacOS::CLT::PKG_PATH
            installation_instructions = MacOS::CLT.installation_instructions
          else
            source = "Xcode"
            path_to_remove = MacOS::Xcode.bundle_path
            installation_instructions = MacOS::Xcode.installation_instructions
          end

          <<~EOS
            The contents of the SDKs in your #{source} installation do not match the SDK folder names.
            A clean reinstall of #{source} should fix this.

            Remove the broken installation before reinstalling:
              sudo rm -rf #{path_to_remove}

            #{installation_instructions}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_cask_software_versions
          super
          add_info "macOS", MacOS.full_version
          add_info "SIP", begin
            csrutil = "/usr/bin/csrutil"
            if File.executable?(csrutil)
              Open3.capture2(csrutil, "status")
                   .first
                   .gsub("This is an unsupported configuration, likely to break in " \
                         "the future and leave your machine in an unknown state.", "")
                   .gsub("System Integrity Protection status: ", "")
                   .delete("\t.")
                   .capitalize
                   .strip
            else
              "N/A"
            end
          end

          nil
        end

        sig { returns(T.nilable(String)) }
        def check_pkgconf_macos_sdk_mismatch
          mismatch = Homebrew::Pkgconf.macos_sdk_mismatch
          return unless mismatch

          Homebrew::Pkgconf.mismatch_warning_message(mismatch)
        end

        sig { returns(T.nilable(String)) }
        def check_cask_quarantine_support
          status, check_output = ::Cask::Quarantine.check_quarantine_support

          case status
          when :quarantine_available
            nil
          when :xattr_broken
            "No Cask quarantine support available: there's no working version of `xattr` on this system."
          when :no_swift
            "No Cask quarantine support available: there's no available version of `swift` on this system."
          when :swift_broken_clt
            <<~EOS
              No Cask quarantine support available: Swift is not working due to missing Command Line Tools.
              #{MacOS::CLT.installation_then_reinstall_instructions}
            EOS
          when :swift_compilation_failed
            <<~EOS
              No Cask quarantine support available: Swift compilation failed.
              This is usually due to a broken or incompatible Command Line Tools installation.
              #{MacOS::CLT.installation_then_reinstall_instructions}
            EOS
          when :swift_runtime_error
            <<~EOS
              No Cask quarantine support available: Swift runtime error.
              Your Command Line Tools installation may be broken or incomplete.
              #{MacOS::CLT.installation_then_reinstall_instructions}
            EOS
          when :swift_not_executable
            <<~EOS
              No Cask quarantine support available: Swift is not executable.
              Your Command Line Tools installation may be incomplete.
              #{MacOS::CLT.installation_then_reinstall_instructions}
            EOS
          when :swift_unexpected_error
            <<~EOS
              No Cask quarantine support available: Swift returned an unexpected error:
              #{check_output}
            EOS
          else
            <<~EOS
              No Cask quarantine support available: unknown reason: #{status.inspect}:
              #{check_output}
            EOS
          end
        end
      end
    end
  end
end

Homebrew::Diagnostic::Checks.prepend(OS::Mac::Diagnostic::Checks)
