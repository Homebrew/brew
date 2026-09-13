# typed: strict
# frozen_string_literal: true

require "utils/text"

require "keg"
require "formula"
require "formulary"
require "utils"
require "version"
require "development_tools"
require "utils/shell"
require "utils/output"
require "cask/caskroom"
require "cask/quarantine"
require "diagnostic/finding"
require "git_repository"
require "missing"
require "system_command"
require "trust"

module Homebrew
  # Module containing diagnostic checks.
  module Diagnostic
    extend Utils::Output::Mixin

    sig { returns(T::Array[T.any(Integer, Symbol)]) }
    def self.support_tiers
      @support_tiers ||= T.let([], T.nilable(T::Array[T.any(Integer, Symbol)]))
    end

    sig { void }
    def self.report_support_tier
      message = Finding.support_tier_message(tier: Finding.support_tier(support_tiers))
      support_tiers.clear
      $stderr.puts "\n", message if message
    end

    at_exit { Homebrew::Diagnostic.report_support_tier }

    sig { params(type: Symbol, fatal: T::Boolean).void }
    def self.checks(type, fatal: true)
      checks = Checks.new
      failed = T.let(false, T::Boolean)
      checks.public_send(type).each do |check|
        Array(checks.public_send(check)).each do |finding|
          support_tiers << finding.tier
          if fatal
            failed = true
            ofail finding.to_s
          else
            opoo finding.to_s
          end
        end
      end
      exit 1 if failed && fatal
    end

    # Diagnostic checks.
    class Checks
      include SystemCommand::Mixin
      include Utils::Output::Mixin

      sig { params(verbose: T::Boolean).void }
      def initialize(verbose: true)
        @verbose = verbose
        @found = T.let([], T::Array[String])
        @seen_prefix_bin = T.let(false, T::Boolean)
        @seen_prefix_sbin = T.let(false, T::Boolean)
        @user_path_1_done = T.let(false, T::Boolean)
        @non_core_taps = T.let([], T.nilable(T::Array[Tap]))
      end

      ############# @!group HELPERS
      # Finds files in `HOMEBREW_PREFIX` *and* /usr/local.
      # Specify paths relative to a prefix, e.g. "include/foo.h".
      # Sets @found for your convenience.
      sig { params(relative_paths: T.any(String, T::Array[String])).void }
      def find_relative_paths(*relative_paths)
        @found = [HOMEBREW_PREFIX, "/usr/local"].uniq.reduce([]) do |found, prefix|
          found + relative_paths.map { |f| File.join(prefix, f) }.select { |f| File.exist? f }
        end
      end

      sig { params(list: T::Array[T.any(Formula, Pathname, Cask::Cask, String)], string: String).returns(String) }
      def append_indented_list(list, string)
        list.reduce(string.dup) { |acc, elem| acc << "  #{elem}\n" }
            .freeze
      end

      sig { params(path: String).returns(String) }
      def user_tilde(path)
        home = Dir.home
        if path == home
          "~"
        else
          path.gsub(%r{^#{home}/}, "~/")
        end
      end

      sig { returns(T.nilable(String)) }
      def none_string
        "<NONE>"
      end

      sig { params(args: T.anything).void }
      def add_info(*args)
        ohai(*args) if @verbose
      end

      sig { params(version: MacOSVersion, intel: T::Boolean).returns(T.nilable(String)) }
      def macos_bottle_remediation(version, intel:)
        return if !intel && !version.outdated_release?
        return if version > :tahoe

        remediation = +"Homebrew no longer builds bottles for this configuration.\n"
        # At the time of writing, MacPorts does not provide a full set of binary packages
        # for Intel Tahoe:
        # https://build.macports.org/builders/ports-26_x86_64-builder
        remediation << if intel && version >= :tahoe
          <<~EOS
            Existing bottles may still work, but updated formulae may build from source.
          EOS
        else
          <<~EOS
            Consider MacPorts, which provides binary packages for this macOS version:
              #{Formatter.url("https://www.macports.org")}
          EOS
        end
      end
      ############# @!endgroup END HELPERS

      sig { returns(T::Array[String]) }
      def fatal_preinstall_checks
        %w[
          check_access_directories
        ].freeze
      end

      sig { returns(T::Array[String]) }
      def fatal_build_from_source_checks
        %w[
          check_for_installed_developer_tools
        ].freeze
      end

      sig { returns(T::Array[String]) }
      def fatal_setup_build_environment_checks
        [].freeze
      end

      sig { returns(T::Array[String]) }
      def supported_configuration_checks
        %w[
          check_homebrew_prefix
          check_for_nix_homebrew
        ].freeze
      end

      sig { returns(T::Array[String]) }
      def build_from_source_checks
        [].freeze
      end

      sig { returns(T::Array[String]) }
      def preinstall_checks
        %w[
          check_untrusted_taps
        ].freeze
      end

      sig { returns(T::Array[String]) }
      def build_error_checks
        supported_configuration_checks + build_from_source_checks
      end

      sig { params(repository_path: GitRepository, desired_origin: String).returns(T.nilable(Finding)) }
      def examine_git_origin(repository_path, desired_origin)
        return if !Utils::Git.available? || !repository_path.git_repository?

        current_origin = repository_path.origin_url

        if current_origin.nil?
          Finding.new(
            <<~EOS,
              Missing #{desired_origin} git origin remote.

              Without a correctly configured origin, Homebrew won't update properly.
            EOS
            remediation: Finding::Remediation.new(
              text:     <<~EOS,
                You can solve this by adding the remote:
                  git -C "#{repository_path}" remote add origin #{Formatter.url(desired_origin)}
              EOS
              commands: [
                "git -C \"#{repository_path}\" remote add origin #{desired_origin}",
              ],
            ),
          )
        elsif !current_origin.match?(%r{#{desired_origin}(\.git|/)?$}i)
          Finding.new(
            <<~EOS,
              The current git origin is:
                #{current_origin}

              With a non-standard origin, Homebrew won't update properly.
            EOS
            remediation: Finding::Remediation.new(
              text:     <<~EOS,
                You can solve this by setting the origin remote:
                  git -C "#{repository_path}" remote set-url origin #{Formatter.url(desired_origin)}
              EOS
              commands: [
                "git -C \"#{repository_path}\" remote set-url origin #{desired_origin}",
              ],
            ),
          )
        end
      end

      sig { params(tap: Tap).returns(T.nilable(Finding)) }
      def broken_tap(tap)
        return unless Utils::Git.available?

        repo = GitRepository.new(HOMEBREW_REPOSITORY)
        return unless repo.git_repository?

        commands = ["rm -rf \"#{tap.path}\"",
                    "brew tap #{tap.name}"]
        finding = Finding.new(
          "#{tap.full_name} was not tapped properly!",
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You can solve this by tapping again:
            EOS
            commands:,
          ),
        )

        return finding if tap.remote.blank?

        tap_head = tap.git_head
        return finding if tap_head.blank?
        return if tap_head != repo.head_ref

        finding
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_installed_developer_tools
        return if DevelopmentTools.installed?

        Finding.new(
          "No developer tools installed.\n",
          remediation: DevelopmentTools.installation_instructions,
        )
      end

      sig { params(dir: String, pattern: String, allow_list: T::Array[String], message: String).returns(T.nilable(String)) }
      def __check_stray_files(dir, pattern, allow_list, message)
        return unless File.directory?(dir)

        files = Dir.chdir(dir) do
          (Dir.glob(pattern) - Dir.glob(allow_list))
            .select { |f| File.file?(f) && !File.symlink?(f) }
            .map do |f|
              f.sub!(%r{/.*}, "/*") unless @verbose
              File.join(dir, f)
            end
            .sort.uniq
        end
        return if files.empty?

        append_indented_list files, message
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_stray_dylibs
        # Dylibs which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
          "libfuse.2.dylib", # MacFuse
          "libfuse3.*.dylib", # MacFuse
          "libfuse_ino64.2.dylib", # MacFuse
          "libfuse-t*.dylib", # FUSE-T
          "libmacfuse_i32.2.dylib", # OSXFuse MacFuse compatibility layer
          "libmacfuse_i64.2.dylib", # OSXFuse MacFuse compatibility layer
          "libosxfuse_i32.2.dylib", # OSXFuse
          "libosxfuse_i64.2.dylib", # OSXFuse
          "libosxfuse.2.dylib", # OSXFuse
          "libTrAPI.dylib", # TrAPI/Endpoint Security VPN
          "libntfs-3g.*.dylib", # NTFS-3G
          "libntfs.*.dylib", # NTFS-3G
          "libublio.*.dylib", # NTFS-3G
          "libUFSDNTFS.dylib", # Paragon NTFS
          "libUFSDExtFS.dylib", # Paragon ExtFS
          "libecomlodr.dylib", # Symantec Endpoint Protection
          "libsymsea*.dylib", # Symantec Endpoint Protection
          "sentinel.dylib", # SentinelOne
          "sentinel-*.dylib", # SentinelOne
          "libASAF.dylib", # Apple Immersive Audio SDK
        ]

        msg = __check_stray_files "/usr/local/lib", "*.dylib", allow_list, <<~EOS
          Unbrewed dylibs were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected dylibs:
        EOS
        Finding.new(msg) if msg.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_stray_static_libs
        # Static libs which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
          "libfuse-t*.a", # FUSE-T
          "libfuse3.a", # FUSE-T
          "libntfs-3g.a", # NTFS-3G
          "libntfs.a", # NTFS-3G
          "libublio.a", # NTFS-3G
          "libappfirewall.a", # Symantec Endpoint Protection
          "libautoblock.a", # Symantec Endpoint Protection
          "libautosetup.a", # Symantec Endpoint Protection
          "libconnectionsclient.a", # Symantec Endpoint Protection
          "liblocationawareness.a", # Symantec Endpoint Protection
          "libpersonalfirewall.a", # Symantec Endpoint Protection
          "libtrustedcomponents.a", # Symantec Endpoint Protection
        ]

        msg = __check_stray_files "/usr/local/lib", "*.a", allow_list, <<~EOS
          Unbrewed static libraries were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected static libraries:
        EOS
        Finding.new(msg) if msg.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_stray_pcs
        # Package-config files which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
          "fuse.pc", # OSXFuse/MacFuse
          "fuse3.pc", # OSXFuse/MacFuse
          "fuse-t.pc", # FUSE-T
          "macfuse.pc", # OSXFuse MacFuse compatibility layer
          "osxfuse.pc", # OSXFuse
          "libntfs-3g.pc", # NTFS-3G
          "libublio.pc", # NTFS-3G
        ]

        msg = __check_stray_files "/usr/local/lib/pkgconfig", "*.pc", allow_list, <<~EOS
          Unbrewed '.pc' files were found in /usr/local/lib/pkgconfig.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected '.pc' files:
        EOS
        Finding.new(msg) if msg.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_stray_las
        allow_list = [
          "libfuse.la", # MacFuse
          "libfuse_ino64.la", # MacFuse
          "libosxfuse_i32.la", # OSXFuse
          "libosxfuse_i64.la", # OSXFuse
          "libosxfuse.la", # OSXFuse
          "libntfs-3g.la", # NTFS-3G
          "libntfs.la", # NTFS-3G
          "libublio.la", # NTFS-3G
        ]

        msg = __check_stray_files "/usr/local/lib", "*.la", allow_list, <<~EOS
          Unbrewed '.la' files were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected '.la' files:
        EOS
        Finding.new(msg) if msg.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_stray_headers
        allow_list = [
          "fuse.h", # MacFuse
          "fuse/**/*.h", # MacFuse
          "fuse3/**/*.h", # MacFuse
          "macfuse/**/*.h", # OSXFuse MacFuse compatibility layer
          "osxfuse/**/*.h", # OSXFuse
          "ntfs/**/*.h", # NTFS-3G
          "ntfs-3g/**/*.h", # NTFS-3G
        ]

        msg = __check_stray_files "/usr/local/include", "**/*.h", allow_list, <<~EOS
          Unbrewed header files were found in /usr/local/include.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected header files:
        EOS
        Finding.new(msg) if msg.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_broken_symlinks
        broken_symlinks = []

        Keg.must_exist_subdirectories.each do |d|
          next unless d.directory?

          d.find do |path|
            broken_symlinks << path if path.symlink? && !Utils::Path.resolved_path_exists?(path)
          end
        end
        return if broken_symlinks.empty?

        Finding.new(
          append_indented_list(broken_symlinks, <<~EOS),
            Broken symlinks were found:
          EOS
          remediation: Finding::Remediation.new(
            text:     <<~EOS,
              Remove them with `brew cleanup`
            EOS
            commands: ["brew cleanup"],
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_tmpdir_sticky_bit
        world_writable = HOMEBREW_TEMP.stat.mode & 0777 == 0777
        return if !world_writable || HOMEBREW_TEMP.sticky?

        commands = ["sudo chmod +t #{HOMEBREW_TEMP}"]
        Finding.new(
          <<~EOS,
            #{HOMEBREW_TEMP} is world-writable but does not have the sticky bit set.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              To set it, run the following command:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_exist_directories
        return if HOMEBREW_PREFIX.writable?

        not_exist_dirs = Keg.must_exist_directories.reject(&:exist?)
        return if not_exist_dirs.empty?

        commands = ["sudo mkdir -p #{not_exist_dirs.join(" ")}",
                    "sudo chown -R #{current_user} #{not_exist_dirs.join(" ")}"]
        Finding.new(
          append_indented_list(not_exist_dirs, <<~EOS),
            The following directories do not exist:
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You should create these directories and change their ownership to your user.
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_access_directories
        not_writable_dirs =
          Keg.must_be_writable_directories.select(&:exist?)
             .reject(&:writable?)
        return if not_writable_dirs.empty?

        commands = ["sudo chown -R #{current_user} #{not_writable_dirs.join(" ")}",
                    "chmod u+w #{not_writable_dirs.join(" ")}"]
        Finding.new(
          append_indented_list(not_writable_dirs, <<~EOS),
            The following directories are not writable by your user:
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You should change the ownership of these directories to your user,
              and make sure that you have write permission.
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_multiple_cellars
        return if HOMEBREW_PREFIX.to_s == HOMEBREW_REPOSITORY.to_s
        return unless (HOMEBREW_REPOSITORY/"Cellar").exist?
        return unless (HOMEBREW_PREFIX/"Cellar").exist?

        commands = ["rm -rf #{HOMEBREW_REPOSITORY}/Cellar"]
        Finding.new(
          <<~EOS,
            You have multiple Cellars.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You should delete #{HOMEBREW_REPOSITORY}/Cellar:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_brew_path
        brew = which("brew", paths)
        return if brew.nil? || File.identical?(brew, HOMEBREW_BREW_FILE)

        Finding.new(
          <<~EOS,
            Another `brew` shadows this Homebrew installation in your PATH:
              #{brew}

            This may be a helper, wrapper or another Homebrew installation.
          EOS
          remediation: path_remediation,
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_user_path_1
        @seen_prefix_bin = false
        @seen_prefix_sbin = false

        message = ""

        paths.each do |p|
          case p
          when "/usr/bin"
            unless @seen_prefix_bin
              # only show the doctor message if there are any conflicts
              # rationale: a default install should not trigger any brew doctor messages
              conflicts = Dir["#{HOMEBREW_PREFIX}/bin/*"]
                          .map { |fn| File.basename fn }
                          .select { |bn| File.exist? "/usr/bin/#{bn}" }

              unless conflicts.empty?
                message = append_indented_list conflicts, <<~EOS
                  /usr/bin occurs before #{HOMEBREW_PREFIX}/bin in your PATH.
                  This means that system-provided programs will be used instead of those
                  provided by Homebrew.

                  The following tools exist at both paths:
                EOS
              end
            end
          when "#{HOMEBREW_PREFIX}/bin"
            @seen_prefix_bin = true
          when "#{HOMEBREW_PREFIX}/sbin"
            @seen_prefix_sbin = true
          end
        end

        @user_path_1_done = true
        Finding.new(message, remediation: path_remediation) if message.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_user_path_2
        check_user_path_1 unless @user_path_1_done
        return if @seen_prefix_bin

        Finding.new(
          <<~EOS,
            Homebrew's "bin" was not found in your PATH.
          EOS
          remediation: path_remediation,
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_user_path_3
        check_user_path_1 unless @user_path_1_done
        return if @seen_prefix_sbin

        # Don't complain about sbin not being in the path if it doesn't exist
        sbin = HOMEBREW_PREFIX/"sbin"
        return unless sbin.directory?
        return if sbin.children.empty?
        return if sbin.children.one? && sbin.children.first.basename.to_s == ".keepme"

        Finding.new(
          <<~EOS,
            Homebrew's "sbin" was not found in your PATH but you have installed
            formulae that put executables in #{HOMEBREW_PREFIX}/sbin.
          EOS
          remediation: path_remediation(sbin.to_s),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_symlinked_cellar
        return unless HOMEBREW_CELLAR.exist?
        return unless HOMEBREW_CELLAR.symlink?

        Finding.new(
          <<~EOS,
            Symlinked Cellars can cause problems.
            Your Homebrew Cellar is a symlink: #{HOMEBREW_CELLAR}
                            which resolves to: #{HOMEBREW_CELLAR.realpath}

            The recommended Homebrew installations are either:
            (A) Have Cellar be a real directory inside of your `$HOMEBREW_PREFIX`
            (B) Symlink "bin/brew" into your prefix, but don't symlink "Cellar".

            Older installations of Homebrew may have created a symlinked Cellar, but this can
            cause problems when two formulae install to locations that are mapped on top of each
            other during the linking step.
          EOS
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_git_version
        minimum_version = ENV.fetch("HOMEBREW_MINIMUM_GIT_VERSION")
        return unless Utils::Git.available?
        return if Utils::Git.version >= Version.new(minimum_version)

        git = Formula["git"]
        git_upgrade_cmd = git.any_version_installed? ? "upgrade" : "install"
        commands = ["brew #{git_upgrade_cmd} git"]
        Finding.new(
          <<~EOS,
            An outdated version (#{Utils::Git.version}) of Git was detected in your PATH.
            Git #{minimum_version} or newer is required for Homebrew.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Please upgrade:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_git
        return if Utils::Git.available?

        commands = ["brew install git"]
        Finding.new(
          <<~EOS,
            Git could not be found in your PATH.
            Homebrew uses Git for several internal functions and some formulae use Git
            checkouts instead of stable tarballs.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You may want to install Git:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_git_newline_settings
        return unless Utils::Git.available?

        autocrlf = HOMEBREW_REPOSITORY.cd do
          Utils.popen_read_text(Utils::Git.git, "config", "--get", "core.autocrlf", err: :err).chomp
        end
        return if autocrlf != "true"

        commands = ["git config --global core.autocrlf input"]
        Finding.new(
          <<~EOS,
            Suspicious Git newline settings found.

            The detected Git newline settings will cause checkout problems:
              core.autocrlf = #{autocrlf}
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              If you are not routinely dealing with Windows-based projects,
              consider removing these by running:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_homebrew_repository_git_hooks
        found = T.let([], T::Array[Pathname])

        hooks_dir = HOMEBREW_REPOSITORY/".git/hooks"
        if hooks_dir.directory?
          found += hooks_dir.children.reject { |path| path.basename.to_s.end_with?(".sample") }.sort_by(&:to_s)
        end

        gitconfig = HOMEBREW_REPOSITORY/".gitconfig"
        found << gitconfig if gitconfig.exist?
        return if found.empty?

        commands = ["rm -rf \"#{HOMEBREW_REPOSITORY}/.git/hooks\" \"#{HOMEBREW_REPOSITORY}/.gitconfig\""]
        Finding.new(
          append_indented_list(found, <<~EOS),
            Git hooks or a repository-local `.gitconfig` were found in your Homebrew repository.
            Homebrew does not use these, and they can break Homebrew operations.

            Paths found:
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Remove them with:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_brew_git_origin
        repo = GitRepository.new(HOMEBREW_REPOSITORY)
        examine_git_origin(repo, Homebrew::EnvConfig.brew_git_remote)
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_nix_homebrew
        return unless OS.nix_managed_homebrew?

        Finding.new(
          <<~EOS,
            Your Homebrew installation is managed by Nix.
            Homebrew does not support Nix-managed installations.
          EOS
          tier: 3,
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_coretap_integrity
        core_tap = CoreTap.instance
        unless core_tap.installed?
          return unless EnvConfig.no_install_from_api?

          core_tap.ensure_installed!
        end

        broken_tap(core_tap) || examine_git_origin(core_tap.git_repository, Homebrew::EnvConfig.core_git_remote)
      end

      sig { returns(T.nilable(Finding)) }
      def check_casktap_integrity
        core_cask_tap = CoreCaskTap.instance
        return unless core_cask_tap.installed?

        broken_tap(core_cask_tap) ||
          examine_git_origin(core_cask_tap.git_repository, core_cask_tap.remote || core_cask_tap.default_remote)
      end

      sig { returns(T.nilable(Finding)) }
      def check_tap_git_branch
        return if ENV["CI"]
        return unless Utils::Git.available?

        deprecated_master = []
        commands = []

        brew_repo = GitRepository.new(HOMEBREW_REPOSITORY)
        deprecated_master << "Homebrew/brew" if brew_repo.branch_name == "master"

        Tap.installed.each do |tap|
          if tap.git_repository.branch_name == "master" && tap.official?
            deprecated_master << tap.name
          elsif !tap.git_repository.default_origin_branch?
            commands << "git -C $(brew --repo #{tap.name}) checkout #{tap.git_repository.origin_branch_name}"
          end
        end

        message = +""

        if deprecated_master.any?
          message += append_indented_list deprecated_master, <<~EOS
            The following repositories are on the deprecated "master" branch.
            The "master" branch sync will stop and this warning will become an error
            when Homebrew 5.2.0 is released (no earlier than 2026-06-10).
            Run `brew update` to migrate to "main":

          EOS
        end

        remediation = nil
        if commands.any?
          message << "\n" if deprecated_master.any?
          message << <<~EOS
            Some taps are not on the default git origin branch and may not receive updates.
          EOS
          remediation = Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              If this is a surprise to you, check out the default branch with:
            EOS
            commands:,
          )
        end

        Finding.new(message, remediation:) if message.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_deprecated_official_taps
        tapped_deprecated_taps =
          Tap.select(&:official?).map(&:repository) & DEPRECATED_OFFICIAL_TAPS

        # TODO: remove this once it's no longer in the default GitHub Actions image
        tapped_deprecated_taps -= ["bundle"] if GitHub::Actions.env_set?

        return if tapped_deprecated_taps.empty?

        Finding.new(
          append_indented_list(tapped_deprecated_taps.map { |name| "Homebrew/homebrew-#{name}" }, <<~EOS),
            You have the following deprecated, official taps tapped:
          EOS
          remediation: Finding::Remediation.new(
            text:     <<~EOS,
              Untap them with `brew untap`.
            EOS
            commands: ["brew untap"],
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_untrusted_taps
        return if Homebrew::EnvConfig.no_require_tap_trust?

        untrusted_taps = Homebrew::Trust.wholly_untrusted_taps
        return if untrusted_taps.empty?

        untrusted_tap_names = untrusted_taps.map(&:name)
        untrusted_tap_name_set = untrusted_tap_names.to_set
        installed_formulae_by_tap = {}
        installed_casks_by_tap = {}
        Formula.racks.each do |rack|
          next unless (keg = Keg.from_rack(rack))
          next unless (tap = keg.tab.tap)
          next unless untrusted_tap_name_set.include?(tap.name)

          installed_formulae = installed_formulae_by_tap[tap.name] ||= []
          installed_formulae << "#{tap.name}/#{rack.basename}"
        rescue
          nil
        end
        installed_formula_message = installed_formulae_by_tap.sort_by(&:first).filter_map do |_tap_name, formulae|
          next if formulae.empty?

          "brew trust --formula #{formulae.sort.join(" ")}"
        end
        Cask::Caskroom.casks.each do |cask|
          next unless (tap = cask.tab.tap)
          next unless untrusted_tap_name_set.include?(tap.name)

          installed_casks = installed_casks_by_tap[tap.name] ||= []
          installed_casks << "#{tap.name}/#{cask.token}"
        end
        installed_cask_message = installed_casks_by_tap.sort_by(&:first).filter_map do |_tap_name, casks|
          next if casks.empty?

          "brew trust --cask #{casks.sort.join(" ")}"
        end
        installed_items_from_untrusted_taps = installed_formula_message.present? || installed_cask_message.present?
        untap_command = ["brew untap #{untrusted_tap_names.join(" ")}"]
        untap_message = append_indented_list(untap_command, <<~EOS)
          Untap them with:
        EOS
        generic_trust_types = []
        generic_trust_commands = []
        if installed_formula_message.blank?
          generic_trust_types << "formulae"
          generic_trust_commands << "brew trust --formula <user>/<tap>/<formula>"
        end
        if installed_cask_message.blank?
          generic_trust_types << "casks"
          generic_trust_commands << "brew trust --cask <user>/<tap>/<cask>"
        end
        generic_trust_types << "commands"
        generic_trust_commands << "brew trust --command <user>/<tap>/<command>"
        generic_trust_prefix = if installed_items_from_untrusted_taps
          "Trust other specific"
        else
          "Trust specific"
        end
        generic_trust_message = append_indented_list generic_trust_commands, <<~EOS
          #{generic_trust_prefix} #{Utils::Text.to_sentence(generic_trust_types)} with:
        EOS
        trust_messages = if installed_items_from_untrusted_taps
          ["Prefer trusting only the specific formulae, casks or commands you need.\n"]
        else
          [untap_message]
        end
        if installed_formula_message.present?
          trust_messages << append_indented_list(installed_formula_message, <<~EOS)
            Trust installed formulae from these taps with:
          EOS
        end
        if installed_cask_message.present?
          trust_messages << append_indented_list(installed_cask_message, <<~EOS)
            Trust installed casks from these taps with:
          EOS
        end
        trust_messages << generic_trust_message
        trust_messages << <<~EOS
          Whole-tap trust is broader and includes all current and future formulae,
          casks and commands from the listed taps. Trust whole taps with:
            brew trust #{untrusted_tap_names.join(" ")}
        EOS
        trust_messages << untap_message if installed_items_from_untrusted_taps
        trust_messages << <<~EOS
          For more information, see:
            #{Formatter.url("https://docs.brew.sh/Tap-Trust")}
        EOS
        untrusted_message = append_indented_list untrusted_tap_names, <<~EOS
          The following taps are not trusted:
        EOS
        untrusted_message += "\nHomebrew is currently ignoring formulae, casks and commands" \
                             "\nfrom these taps because tap trust is required."

        Finding.new(
          untrusted_message,
          links:       ["https://docs.brew.sh/Tap-Trust"],
          remediation: trust_messages.join,
        )
      end

      sig { params(formula: Formula).returns(T::Boolean) }
      def __check_linked_brew!(formula)
        formula.installed_prefixes.each do |prefix|
          prefix.find do |src|
            next if src == prefix

            dst = HOMEBREW_PREFIX + src.relative_path_from(prefix)
            return true if dst.symlink? && src == Utils::Path.resolved_path(dst)
          end
        end

        false
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_other_frameworks
        # Other frameworks that are known to cause problems when present
        frameworks_to_check = %w[
          expat.framework
          libexpat.framework
          libcurl.framework
        ]
        frameworks_found = frameworks_to_check
                           .map { |framework| "/Library/Frameworks/#{framework}" }
                           .select { |framework| File.exist? framework }
        return if frameworks_found.empty?

        Finding.new(
          <<~EOS,
            Some frameworks can be picked up by CMake's build system and will likely
            cause the build to fail.
          EOS
          remediation: append_indented_list(frameworks_found, <<~EOS),
            To compile CMake, you may wish to move these out of the way:
          EOS
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_tmpdir
        tmpdir = ENV.fetch("TMPDIR", nil)
        return if tmpdir.nil? || File.directory?(tmpdir)

        Finding.new(
          <<~EOS,
            TMPDIR #{tmpdir.inspect} doesn't exist.
          EOS
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_missing_deps
        return if !HOMEBREW_CELLAR.exist? && !Cask::Caskroom.path.exist?

        missing = Set.new
        Homebrew::Missing.deps(Formula.installed, Cask::Caskroom.casks).each_value do |deps|
          missing.merge(deps)
        end
        return if missing.empty?

        commands = ["brew install #{missing.sort * " "}"]
        Finding.new(
          <<~EOS,
            Some installed formulae or casks are missing dependencies.
            Run `brew missing` for more details.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              You should `brew install` the missing dependencies:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_deprecated_disabled
        return unless HOMEBREW_CELLAR.exist?

        deprecated_or_disabled = Formula.installed.select { |f| f.deprecated? || f.disabled? }
        return if deprecated_or_disabled.empty?

        Finding.new(
          "Some installed formulae are deprecated or disabled.",
          affects:     deprecated_or_disabled.map(&:full_name),
          remediation: append_indented_list(deprecated_or_disabled.sort_by(&:full_name).uniq, <<~EOS),
            You should find replacements for the following formulae:

          EOS
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_deprecated_disabled
        deprecated_or_disabled = Cask::Caskroom.casks.select(&:deprecated?)
        deprecated_or_disabled += Cask::Caskroom.casks.select(&:disabled?)
        return if deprecated_or_disabled.empty?

        Finding.new(
          "Some installed casks are deprecated or disabled.",
          affects:     deprecated_or_disabled.map(&:token),
          remediation: append_indented_list(deprecated_or_disabled.sort_by(&:token).uniq, <<~EOS),
            You should find replacements for the following casks:

          EOS
        )
      end

      sig { returns(T::Array[Finding]) }
      def check_git_status
        return [] unless Utils::Git.available?

        repos = {
          "Homebrew/brew"          => HOMEBREW_REPOSITORY,
          "Homebrew/homebrew-core" => CoreTap.instance.path,
          "Homebrew/homebrew-cask" => CoreCaskTap.instance.path,
        }

        status = []
        repos.each do |name, path|
          finding = __tap_git_status(name, path)
          status << finding if finding.present?
        end

        status
      end

      sig { params(tap: String, path: Pathname).returns(T.nilable(Finding)) }
      def __tap_git_status(tap, path)
        return unless path.exist?

        status = path.cd do
          Utils.popen_read_text(Utils::Git.git, "status", "--untracked-files=all", "--porcelain", err: File::NULL)
        end
        return if status.blank?

        message = <<~EOS
          You have uncommitted modifications to #{tap}.
        EOS
        commands = ["git -C \"#{path}\" stash -u && git -C \"#{path}\" clean -d -f"]
        remediation = Finding::Remediation.new(
          text:     append_indented_list(commands, <<~EOS),
            If this is a surprise to you, then you should stash these modifications.
            Stashing returns Homebrew to a pristine state but can be undone
            should you later need to do so for some reason.

          EOS
          commands:,
        )

        modified = status.split("\n").map(&:strip)
        message += append_indented_list modified, <<~EOS
          Uncommitted files:

        EOS
        Finding.new(message, affects: modified, remediation:) if message.present?
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_non_prefixed_coreutils
        coreutils = Formula["coreutils"]
        return unless coreutils.any_version_installed?

        gnubin = %W[#{coreutils.opt_libexec}/gnubin #{coreutils.libexec}/gnubin]
        return unless paths.intersect?(gnubin)

        Finding.new(
          <<~EOS,
            Putting non-prefixed coreutils in your path can cause GMP builds to fail.
          EOS
        )
      rescue FormulaUnavailableError
        nil
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_pydistutils_cfg_in_home
        return unless File.exist? "#{Dir.home}/.pydistutils.cfg"

        Finding.new(
          <<~EOS,
            A '.pydistutils.cfg' file was found in $HOME, which may cause Python
            builds to fail. See:
              #{Formatter.url("https://bugs.python.org/issue6138")}
              #{Formatter.url("https://bugs.python.org/issue4655")}
          EOS
          links: [
            "https://bugs.python.org/issue6138",
            "https://bugs.python.org/issue4655",
          ],
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_unreadable_installed_formula
        formula_unavailable_exceptions = []
        Formula.racks.each do |rack|
          Formulary.from_rack(rack)
        rescue FormulaUnreadableError, FormulaClassUnavailableError,
               TapFormulaUnreadableError, TapFormulaClassUnavailableError => e
          formula_unavailable_exceptions << e
        rescue Homebrew::UntrustedTapError, FormulaUnavailableError, TapFormulaAmbiguityError
          nil
        end
        return if formula_unavailable_exceptions.empty?

        Finding.new(
          append_indented_list(formula_unavailable_exceptions.map { |s| "#{s}\n" }, <<~EOS),
            Some installed formulae are not readable:
          EOS
          affects: formula_unavailable_exceptions,
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_unlinked_but_not_keg_only
        unlinked = Formula.racks.reject do |rack|
          next true if (HOMEBREW_LINKED_KEGS/rack.basename).directory?

          begin
            Formulary.from_rack(rack).keg_only?
          rescue Homebrew::UntrustedTapError
            true
          rescue FormulaUnavailableError, TapFormulaAmbiguityError
            false
          end
        end.map(&:basename)
        return if unlinked.empty?

        Finding.new(
          <<~EOS,
            You have unlinked kegs in your Cellar.
            Leaving kegs unlinked can lead to build-trouble and cause formulae that depend on
            those kegs to fail to run properly once built.
          EOS
          affects:     unlinked.map(&:to_s),
          remediation: Finding::Remediation.new(
            text:     append_indented_list(unlinked, <<~EOS),
              Run `brew link` on these:
            EOS
            commands: unlinked.map { |unlink| "brew link #{unlink}" },
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_external_cmd_name_conflict
        cmds = Commands.tap_cmd_directories.flat_map { |p| Dir["#{p}/brew-*"] }.uniq
        cmds = cmds.select { |cmd| File.file?(cmd) && File.executable?(cmd) }
        cmd_map = {}
        cmds.each do |cmd|
          cmd_name = File.basename(cmd, ".rb")
          cmd_map[cmd_name] ||= []
          cmd_map[cmd_name] << cmd
        end
        cmd_map.reject! { |_cmd_name, cmd_paths| cmd_paths.size == 1 }
        return if cmd_map.empty?

        if ENV["CI"].present? && cmd_map.keys.length == 1 &&
           cmd_map.keys.first == "brew-test-bot"
          return
        end

        message = "You have external commands with conflicting names.\n"
        cmd_map.each do |cmd_name, cmd_paths|
          message += append_indented_list cmd_paths, <<~EOS
            Found command `#{cmd_name}` in the following places:
          EOS
        end

        Finding.new(message)
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_tap_ruby_files_locations
        bad_tap_files = {}
        Tap.installed.each do |tap|
          unused_formula_dirs = tap.potential_formula_dirs - [tap.formula_dir]
          unused_formula_dirs.each do |dir|
            next unless dir.exist?

            dir.children.each do |path|
              next if path.extname != ".rb"

              bad_tap_files[tap] ||= []
              bad_tap_files[tap] << path
            end
          end
        end
        return if bad_tap_files.empty?

        Finding.new(bad_tap_files.keys.map do |tap|
          append_indented_list bad_tap_files[tap], <<~EOS
            Found Ruby file outside #{tap} tap formula directory.
            (#{tap.formula_dir}):
          EOS
        end.join("\n"))
      end

      sig { returns(T.nilable(Finding)) }
      def check_homebrew_prefix
        return if Homebrew.default_prefix?
        return if ENV["HOMEBREW_INTEGRATION_TEST"]

        Finding.new(
          <<~EOS,
            Your Homebrew's prefix is not #{Homebrew::DEFAULT_PREFIX}.

            Most of Homebrew's bottles (binary packages) can only be used with the default prefix.
          EOS
          tier:        3,
          remediation: "Consider uninstalling Homebrew and reinstalling into the default prefix.",
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_deleted_formula
        kegs = Keg.all

        deleted_formulae = kegs.filter_map do |keg|
          tap = keg.tab.tap
          tap_keg_name = tap ? "#{tap}/#{keg.name}" : keg.name

          loadable = [
            Formulary::FromAPILoader,
            Formulary::FromTapLoader,
            Formulary::FromNameLoader,
          ].any? do |loader_class|
            loader = begin
              loader_class.try_new(tap_keg_name, warn: false)
            rescue TapFormulaAmbiguityError => e
              e.loaders.first
            end

            loader.instance_of?(Formulary::FromTapLoader) ? loader.path.exist? : loader.present?
          end

          keg.name unless loadable
        end.uniq

        return if deleted_formulae.blank?

        Finding.new(
          <<~EOS,
            Some installed kegs have no formulae!
            This means they were either deleted or installed manually.

          EOS
          affects:     deleted_formulae,
          remediation: append_indented_list(deleted_formulae, <<~EOS),
            You should find replacements for the following formulae:

          EOS
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_unnecessary_core_tap
        return if Homebrew::EnvConfig.developer?
        return if Homebrew::EnvConfig.no_install_from_api?
        return if Homebrew::EnvConfig.devcmdrun?
        return unless CoreTap.instance.installed?

        commands = ["brew untap #{CoreTap.instance.name}"]
        Finding.new(
          <<~EOS,
            You have an unnecessary local Core tap!
            This can cause problems installing up-to-date formulae.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Please remove it by running:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_unnecessary_cask_tap
        return if Homebrew::EnvConfig.developer?
        return if Homebrew::EnvConfig.no_install_from_api?
        return if Homebrew::EnvConfig.devcmdrun?

        cask_tap = CoreCaskTap.instance
        return unless cask_tap.installed?

        commands = ["brew untap #{cask_tap.name}"]
        Finding.new(
          <<~EOS,
            You have an unnecessary local Cask tap.
            This can cause problems installing up-to-date casks.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Please remove it by running:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_deprecated_cask_taps
        tapped_caskroom_taps = ::Tap.select { |t| t.user == "caskroom" || t.name == "phinze/cask" }
                                    .map(&:name)
        return if tapped_caskroom_taps.empty?

        commands = ["brew untap #{tapped_caskroom_taps.join(" ")}"]
        Finding.new(
          append_indented_list(tapped_caskroom_taps, <<~EOS),
            You have the following deprecated Cask taps installed:
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Please remove it by running:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_software_versions
        add_info "Homebrew Version", HOMEBREW_VERSION

        nil
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_install_location
        locations = Dir.glob(HOMEBREW_CELLAR.join("brew-cask", "*")).reverse
        return if locations.empty?

        Finding.new(
          append_indented_list(locations, <<~EOS),
            Legacy installs at:
          EOS
          remediation: Finding::Remediation.new(
            text:     <<~EOS,
              Run `brew uninstall --force brew-cask`.
            EOS
            commands: ["brew uninstall --force brew-cask"],
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_staging_location
        # Skip this check when running CI since the staging path is not writable for security reasons
        return if GitHub::Actions.env_set?

        path = Cask::Caskroom.path

        add_info "Cask Staging Location", user_tilde(path.to_s)

        return if !path.exist? || path.writable?

        commands = ["sudo chown -R #{current_user} #{user_tilde(path.to_s)}"]
        Finding.new(
          <<~EOS,
            The staging path #{user_tilde(path.to_s)} is not writable by the current user.
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              To fix this, run:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_corrupt_dirs
        corrupt = Cask::Caskroom.corrupt_cask_dirs
        return if corrupt.empty?

        commands = corrupt.map { |token| "brew reinstall --cask --force #{token}" }
        Finding.new(
          append_indented_list(corrupt.map { |token| "#{Cask::Caskroom.path}/#{token}" }, <<~EOS),
            Some directories in the Caskroom do not have valid metadata.
            The following #{Utils.pluralize("cask", corrupt.count)} cannot be upgraded as-is:
          EOS
          remediation: Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              To fix this, run:
            EOS
            commands:,
          ),
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_taps
        error_tap_paths = []

        taps = (Tap.to_a + [CoreCaskTap.instance]).uniq

        taps_info = taps.filter_map do |tap|
          cask_count = begin
            tap.cask_files.count
          rescue
            error_tap_paths << tap.path
            0
          end
          next if cask_count.zero?

          "#{tap.path} (#{Utils.pluralize("cask", cask_count, include_count: true)})"
        end
        add_info "Cask Taps:", taps_info

        taps_string = Utils.pluralize("tap", error_tap_paths.count)
        return unless error_tap_paths.present?

        Finding.new("Unable to read from cask #{taps_string}: #{Utils::Text.to_sentence(error_tap_paths)}")
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_load_path
        paths = $LOAD_PATH.map { user_tilde(it) }

        add_info "$LOAD_PATHS", paths.presence || none_string

        Finding.new("$LOAD_PATH is empty") if paths.blank?
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_environment_variables
        environment_variables = %w[
          RUBYLIB
          RUBYOPT
          RUBYPATH
          RBENV_VERSION
          CHRUBY_VERSION
          GEM_HOME
          GEM_PATH
          BUNDLE_PATH
          PATH
          SHELL
          HOMEBREW_CASK_OPTS
        ]

        locale_variables = ENV.keys.grep(/^(?:LC_\S+|LANG|LANGUAGE)\Z/).sort

        cask_environment_variables = (locale_variables + environment_variables).sort.filter_map do |var|
          next unless ENV.key?(var)

          %Q(#{var}="#{Utils::Shell.sh_quote(ENV.fetch(var))}")
        end
        add_info "Cask Environment Variables:", cask_environment_variables

        nil
      end

      sig { returns(T.nilable(Finding)) }
      def check_cask_xattr
        # If quarantine is not available, a warning is already shown by check_cask_quarantine_support so just return
        return unless Cask::Quarantine.available?
        return Finding.new("Unable to find `xattr`.") unless File.exist?("/usr/bin/xattr")

        result = system_command "/usr/bin/xattr", args: ["-h"]

        return if result.status.success?

        if result.stderr.include? "ImportError: No module named pkg_resources"
          result = Utils.popen_read "/usr/bin/python", "--version", err: :out

          if result.include? "Python 2.7"
            commands = ["sudo /usr/bin/python -m pip install -I setuptools"]
            Finding.new(
              <<~EOS,
                Your Python installation has a broken version of setuptools.
              EOS
              remediation: Finding::Remediation.new(
                text:     append_indented_list(commands, <<~EOS),
                  To this fix, reinstall macOS or run:
                EOS
                commands:,
              ),
            )
          else
            commands = ["defaults write com.apple.versioner.python Version 2.7"]
            Finding.new(
              <<~EOS,
                The system Python version is wrong.
              EOS
              remediation: Finding::Remediation.new(
                text:     append_indented_list(commands, <<~EOS),
                  To fix this, run:
                EOS
                commands:,
              ),
            )
          end
        elsif result.stderr.include? "pkg_resources.DistributionNotFound"
          Finding.new("Your Python installation is unable to find `xattr`.")
        else
          Finding.new("unknown xattr error: #{result.stderr.split("\n").last}")
        end
      end

      sig { returns(T::Array[Tap]) }
      def non_core_taps
        @non_core_taps ||= Tap.installed.reject(&:core_tap?).reject(&:core_cask_tap?)
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_duplicate_formulae
        return if ENV["HOMEBREW_TEST_BOT"].present?

        core_formula_names = CoreTap.instance.formula_names
        shadowed_formula_full_names = non_core_taps.flat_map do |tap|
          tap_formula_names = tap.formula_names.map { |s| s.delete_prefix("#{tap.name}/") }
          (core_formula_names & tap_formula_names).map { |f| "#{tap.name}/#{f}" }
        end.compact.sort
        return if shadowed_formula_full_names.empty?

        installed_formula_tap_names = Formula.installed.filter_map(&:tap).uniq.reject(&:official?).map(&:name)
        shadowed_formula_tap_names = shadowed_formula_full_names.filter_map { |s| Utils.tap_from_full_name(s) }.uniq
        unused_shadowed_formula_tap_names = (shadowed_formula_tap_names - installed_formula_tap_names).sort

        remediation = if unused_shadowed_formula_tap_names.empty?
          "Their taps are in use, so you must use these full names throughout Homebrew."
        else
          commands = ["brew untap #{unused_shadowed_formula_tap_names.join(" ")}"]
          Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Some of these can be resolved with:
            EOS
            commands:,
          )
        end

        Finding.new(
          append_indented_list(shadowed_formula_full_names, <<~EOS),
            The following formulae have the same name as core formulae:
          EOS
          remediation:,
        )
      end

      sig { returns(T.nilable(Finding)) }
      def check_for_duplicate_casks
        return if ENV["HOMEBREW_TEST_BOT"].present?

        core_cask_names = CoreCaskTap.instance.cask_tokens
        shadowed_cask_full_names = non_core_taps.flat_map do |tap|
          tap_cask_names = tap.cask_tokens.map { |s| s.delete_prefix("#{tap.name}/") }
          (core_cask_names & tap_cask_names).map { |f| "#{tap.name}/#{f}" }
        end.compact.sort
        return if shadowed_cask_full_names.empty?

        installed_cask_tap_names = Cask::Caskroom.casks.filter_map(&:tap).uniq.reject(&:official?).map(&:name)
        shadowed_cask_tap_names = shadowed_cask_full_names.filter_map { |s| Utils.tap_from_full_name(s) }.uniq
        unused_shadowed_cask_tap_names = (shadowed_cask_tap_names - installed_cask_tap_names).sort

        remediation = if unused_shadowed_cask_tap_names.empty?
          "Their taps are in use, so you must use these full names throughout Homebrew.\n"
        else
          commands = ["brew untap #{unused_shadowed_cask_tap_names.join(" ")}"]
          Finding::Remediation.new(
            text:     append_indented_list(commands, <<~EOS),
              Some of these can be resolved with:
            EOS
            commands:,
          )
        end

        Finding.new(
          append_indented_list(shadowed_cask_full_names, <<~EOS),
            The following casks have the same name as core casks:
          EOS
          affects:     shadowed_cask_full_names,
          remediation:,
        )
      end

      sig { returns(T::Array[String]) }
      def all
        methods.map(&:to_s).grep(/^check_/).sort
      end

      sig { returns(T::Array[String]) }
      def cask_checks
        all.grep(/^check_cask_/)
      end

      sig { returns(String) }
      def current_user
        ENV.fetch("USER", "$(whoami)")
      end

      private

      sig { params(path: String).returns(Finding::Remediation) }
      def path_remediation(path = "#{HOMEBREW_PREFIX}/bin")
        prepend_path = Utils::Shell.prepend_path_in_profile(path)
        Finding::Remediation.new(
          text:     <<~EOS,
            Consider setting your PATH for example like so:
              #{prepend_path}
          EOS
          commands: [prepend_path].compact,
        )
      end

      sig { returns(T::Array[String]) }
      def paths
        @paths ||= T.let(ORIGINAL_PATHS.uniq.map(&:to_s), T.nilable(T::Array[String]))
      end
    end
  end
end

require "extend/os/diagnostic"
