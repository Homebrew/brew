# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "keg"
require "language/python"
require "formula"
require "formulary"
require "version"
require "development_tools"
require "utils/shell"
require "system_config"
require "cask/caskroom"
require "cask/quarantine"
require "system_command"

module Homebrew
  # Module containing diagnostic checks.
  module Diagnostic
    def self.missing_deps(formulae, hide = [])
      missing = {}
      formulae.each do |f|
        missing_dependencies = f.missing_dependencies(hide: hide)
        next if missing_dependencies.empty?

        yield f.full_name, missing_dependencies if block_given?
        missing[f.full_name] = missing_dependencies
      end
      missing
    end

    def self.checks(type, fatal: true)
      @checks ||= Checks.new
      failed = T.let(false, T::Boolean)
      @checks.public_send(type).each do |check|
        out = @checks.public_send(check)
        next if out.nil?

        if fatal
          failed ||= true
          ofail out
        else
          opoo out
        end
      end
      exit 1 if failed && fatal
    end

    # Diagnostic checks.
    class Checks
      include SystemCommand::Mixin

      def initialize(verbose: true)
        @verbose = verbose
      end

      ############# @!group HELPERS
      # Finds files in `HOMEBREW_PREFIX` *and* /usr/local.
      # Specify paths relative to a prefix, e.g. "include/foo.h".
      # Sets @found for your convenience.
      def find_relative_paths(*relative_paths)
        @found = [HOMEBREW_PREFIX, "/usr/local"].uniq.reduce([]) do |found, prefix|
          found + relative_paths.map { |f| File.join(prefix, f) }.select { |f| File.exist? f }
        end
      end

      sig { params(list: T::Array[T.any(Formula, Pathname, String)], string: String).returns(String) }
      def inject_file_list(list, string)
        list.reduce(string.dup) { |acc, elem| acc << "  #{elem}\n" }
            .freeze
      end

      def user_tilde(path)
        path.gsub(Dir.home, "~")
      end

      sig { returns(String) }
      def none_string
        "<NONE>"
      end

      def add_info(*args)
        ohai(*args) if @verbose
      end
      ############# @!endgroup END HELPERS

      def fatal_preinstall_checks
        %w[
          check_access_directories
        ].freeze
      end

      def fatal_build_from_source_checks
        %w[
          check_for_installed_developer_tools
        ].freeze
      end

      def fatal_setup_build_environment_checks
        [].freeze
      end

      def supported_configuration_checks
        [].freeze
      end

      def build_from_source_checks
        [].freeze
      end

      def build_error_checks
        supported_configuration_checks + build_from_source_checks
      end

      def please_create_pull_requests(what = "unsupported configuration")
        <<~EOS
          It is expected behaviour that some formulae will fail to build in this #{what}.
          It is expected behaviour that Homebrew will be buggy and slow.
          Do not create any issues about this on Homebrew's GitHub repositories.
          Do not create any issues even if you think this message is unrelated.
          Any opened issues will be immediately closed without response.
          Do not ask for help from Homebrew or its maintainers on social media.
          You may ask for help in Homebrew's discussions but are unlikely to receive a response.
          Try to figure out the problem yourself and submit a fix as a pull request.
          We will review it but may or may not accept it.
        EOS
      end

      sig { params(repository_path: GitRepository, desired_origin: String).returns(T.nilable(String)) }
      def examine_git_origin(repository_path, desired_origin)
        return if !Utils::Git.available? || !repository_path.git_repository?

        current_origin = repository_path.origin_url

        if current_origin.nil?
          <<~EOS
            Missing #{desired_origin} git origin remote.

            Without a correctly configured origin, Homebrew won't update
            properly. You can solve this by adding the remote:
              git -C "#{repository_path}" remote add origin #{Formatter.url(desired_origin)}
          EOS
        elsif !current_origin.match?(%r{#{desired_origin}(\.git|/)?$}i)
          <<~EOS
            Suspicious #{desired_origin} git origin remote found.
            The current git origin is:
              #{current_origin}

            With a non-standard origin, Homebrew won't update properly.
            You can solve this by setting the origin remote:
              git -C "#{repository_path}" remote set-url origin #{Formatter.url(desired_origin)}
          EOS
        end
      end

      def broken_tap(tap)
        return unless Utils::Git.available?

        repo = GitRepository.new(HOMEBREW_REPOSITORY)
        return unless repo.git_repository?

        message = <<~EOS
          #{tap.full_name} was not tapped properly! Run:
            rm -rf "#{tap.path}"
            brew tap #{tap.name}
        EOS

        return message if tap.remote.blank?

        tap_head = tap.git_head
        return message if tap_head.blank?
        return if tap_head != repo.head_ref

        message
      end

      def check_for_installed_developer_tools
        return if DevelopmentTools.installed?

        <<~EOS
          No developer tools installed.
          #{DevelopmentTools.installation_instructions}
        EOS
      end

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

        inject_file_list(files, message)
      end

      def check_for_stray_dylibs
        # Dylibs which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
          "libfuse.2.dylib", # MacFuse
          "libfuse_ino64.2.dylib", # MacFuse
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
        ]

        __check_stray_files "/usr/local/lib", "*.dylib", allow_list, <<~EOS
          Unbrewed dylibs were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected dylibs:
        EOS
      end

      def check_for_stray_static_libs
        # Static libs which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
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

        __check_stray_files "/usr/local/lib", "*.a", allow_list, <<~EOS
          Unbrewed static libraries were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected static libraries:
        EOS
      end

      def check_for_stray_pcs
        # Package-config files which are generally OK should be added to this list,
        # with a short description of the software they come with.
        allow_list = [
          "fuse.pc", # OSXFuse/MacFuse
          "macfuse.pc", # OSXFuse MacFuse compatibility layer
          "osxfuse.pc", # OSXFuse
          "libntfs-3g.pc", # NTFS-3G
          "libublio.pc", # NTFS-3G
        ]

        __check_stray_files "/usr/local/lib/pkgconfig", "*.pc", allow_list, <<~EOS
          Unbrewed '.pc' files were found in /usr/local/lib/pkgconfig.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected '.pc' files:
        EOS
      end

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

        __check_stray_files "/usr/local/lib", "*.la", allow_list, <<~EOS
          Unbrewed '.la' files were found in /usr/local/lib.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected '.la' files:
        EOS
      end

      def check_for_stray_headers
        allow_list = [
          "fuse.h", # MacFuse
          "fuse/**/*.h", # MacFuse
          "macfuse/**/*.h", # OSXFuse MacFuse compatibility layer
          "osxfuse/**/*.h", # OSXFuse
          "ntfs/**/*.h", # NTFS-3G
          "ntfs-3g/**/*.h", # NTFS-3G
        ]

        __check_stray_files "/usr/local/include", "**/*.h", allow_list, <<~EOS
          Unbrewed header files were found in /usr/local/include.
          If you didn't put them there on purpose they could cause problems when
          building Homebrew formulae and may need to be deleted.

          Unexpected header files:
        EOS
      end

      def check_for_broken_symlinks
        broken_symlinks = []

        Keg.must_exist_subdirectories.each do |d|
          next unless d.directory?

          d.find do |path|
            broken_symlinks << path if path.symlink? && !path.resolved_path_exists?
          end
        end
        return if broken_symlinks.empty?

        inject_file_list broken_symlinks, <<~EOS
          Broken symlinks were found. Remove them with `brew cleanup`:
        EOS
      end

      def check_tmpdir_sticky_bit
        world_writable = HOMEBREW_TEMP.stat.mode & 0777 == 0777
        return if !world_writable || HOMEBREW_TEMP.sticky?

        <<~EOS
          #{HOMEBREW_TEMP} is world-writable but does not have the sticky bit set.
          To set it, run the following command:
            sudo chmod +t #{HOMEBREW_TEMP}
        EOS
      end
      alias generic_check_tmpdir_sticky_bit check_tmpdir_sticky_bit

      def check_exist_directories
        return if HOMEBREW_PREFIX.writable?

        not_exist_dirs = Keg.must_exist_directories.reject(&:exist?)
        return if not_exist_dirs.empty?

        <<~EOS
          The following directories do not exist:
          #{not_exist_dirs.join("\n")}

          You should create these directories and change their ownership to your user.
            sudo mkdir -p #{not_exist_dirs.join(" ")}
            sudo chown -R #{current_user} #{not_exist_dirs.join(" ")}
        EOS
      end

      def check_access_directories
        not_writable_dirs =
          Keg.must_be_writable_directories.select(&:exist?)
             .reject(&:writable?)
        return if not_writable_dirs.empty?

        <<~EOS
          The following directories are not writable by your user:
          #{not_writable_dirs.join("\n")}

          You should change the ownership of these directories to your user.
            sudo chown -R #{current_user} #{not_writable_dirs.join(" ")}

          And make sure that your user has write permission.
            chmod u+w #{not_writable_dirs.join(" ")}
        EOS
      end

      def check_multiple_cellars
        return if HOMEBREW_PREFIX.to_s == HOMEBREW_REPOSITORY.to_s
        return unless (HOMEBREW_REPOSITORY/"Cellar").exist?
        return unless (HOMEBREW_PREFIX/"Cellar").exist?

        <<~EOS
          You have multiple Cellars.
          You should delete #{HOMEBREW_REPOSITORY}/Cellar:
            rm -rf #{HOMEBREW_REPOSITORY}/Cellar
        EOS
      end

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
                message = inject_file_list conflicts, <<~EOS
                  /usr/bin occurs before #{HOMEBREW_PREFIX}/bin in your PATH.
                  This means that system-provided programs will be used instead of those
                  provided by Homebrew. Consider setting your PATH so that
                  #{HOMEBREW_PREFIX}/bin occurs before /usr/bin. Here is a one-liner:
                    #{Utils::Shell.prepend_path_in_profile("#{HOMEBREW_PREFIX}/bin")}

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

        message unless message.empty?
      end

      def check_user_path_2
        return if @seen_prefix_bin

        <<~EOS
          Homebrew's "bin" was not found in your PATH.
          Consider setting your PATH for example like so:
            #{Utils::Shell.prepend_path_in_profile("#{HOMEBREW_PREFIX}/bin")}
        EOS
      end

      def check_user_path_3
        return if @seen_prefix_sbin

        # Don't complain about sbin not being in the path if it doesn't exist
        sbin = HOMEBREW_PREFIX/"sbin"
        return unless sbin.directory?
        return if sbin.children.empty?
        return if sbin.children.one? && sbin.children.first.basename.to_s == ".keepme"

        <<~EOS
          Homebrew's "sbin" was not found in your PATH but you have installed
          formulae that put executables in #{HOMEBREW_PREFIX}/sbin.
          Consider setting your PATH for example like so:
            #{Utils::Shell.prepend_path_in_profile("#{HOMEBREW_PREFIX}/sbin")}
        EOS
      end

      def check_for_symlinked_cellar
        return unless HOMEBREW_CELLAR.exist?
        return unless HOMEBREW_CELLAR.symlink?

        <<~EOS
          Symlinked Cellars can cause problems.
          Your Homebrew Cellar is a symlink: #{HOMEBREW_CELLAR}
                          which resolves to: #{HOMEBREW_CELLAR.realpath}

          The recommended Homebrew installations are either:
          (A) Have Cellar be a real directory inside of your HOMEBREW_PREFIX
          (B) Symlink "bin/brew" into your prefix, but don't symlink "Cellar".

          Older installations of Homebrew may have created a symlinked Cellar, but this can
          cause problems when two formulae install to locations that are mapped on top of each
          other during the linking step.
        EOS
      end

      def check_git_version
        minimum_version = ENV.fetch("HOMEBREW_MINIMUM_GIT_VERSION")
        return unless Utils::Git.available?
        return if Version.new(Utils::Git.version) >= Version.new(minimum_version)

        git = Formula["git"]
        git_upgrade_cmd = git.any_version_installed? ? "upgrade" : "install"
        <<~EOS
          An outdated version (#{Utils::Git.version}) of Git was detected in your PATH.
          Git #{minimum_version} or newer is required for Homebrew.
          Please upgrade:
            brew #{git_upgrade_cmd} git
        EOS
      end

      def check_for_git
        return if Utils::Git.available?

        <<~EOS
          Git could not be found in your PATH.
          Homebrew uses Git for several internal functions and some formulae use Git
          checkouts instead of stable tarballs. You may want to install Git:
            brew install git
        EOS
      end

      def check_git_newline_settings
        return unless Utils::Git.available?

        autocrlf = HOMEBREW_REPOSITORY.cd { `git config --get core.autocrlf`.chomp }
        return if autocrlf != "true"

        <<~EOS
          Suspicious Git newline settings found.

          The detected Git newline settings will cause checkout problems:
            core.autocrlf = #{autocrlf}

          If you are not routinely dealing with Windows-based projects,
          consider removing these by running:
            git config --global core.autocrlf input
        EOS
      end

      def check_brew_git_origin
        repo = GitRepository.new(HOMEBREW_REPOSITORY)
        examine_git_origin(repo, Homebrew::EnvConfig.brew_git_remote)
      end

      def check_coretap_integrity
        core_tap = CoreTap.instance
        unless core_tap.installed?
          return unless EnvConfig.no_install_from_api?

          core_tap.ensure_installed!
        end

        broken_tap(core_tap) || examine_git_origin(core_tap.git_repository, Homebrew::EnvConfig.core_git_remote)
      end

      def check_casktap_integrity
        core_cask_tap = CoreCaskTap.instance
        return unless core_cask_tap.installed?

        broken_tap(core_cask_tap) || examine_git_origin(core_cask_tap.git_repository, core_cask_tap.remote)
      end

      sig { returns(T.nilable(String)) }
      def check_tap_git_branch
        return if ENV["CI"]
        return unless Utils::Git.available?

        commands = Tap.installed.filter_map do |tap|
          next if tap.git_repository.default_origin_branch?

          "git -C $(brew --repo #{tap.name}) checkout #{tap.git_repository.origin_branch_name}"
        end

        return if commands.blank?

        <<~EOS
          Some taps are not on the default git origin branch and may not receive
          updates. If this is a surprise to you, check out the default branch with:
            #{commands.join("\n  ")}
        EOS
      end

      def check_deprecated_official_taps
        tapped_deprecated_taps =
          Tap.select(&:official?).map(&:repository) & DEPRECATED_OFFICIAL_TAPS
        return if tapped_deprecated_taps.empty?

        <<~EOS
          You have the following deprecated, official taps tapped:
            Homebrew/homebrew-#{tapped_deprecated_taps.join("\n  Homebrew/homebrew-")}
          Untap them with `brew untap`.
        EOS
      end

      def __check_linked_brew(formula)
        formula.installed_prefixes.each do |prefix|
          prefix.find do |src|
            next if src == prefix

            dst = HOMEBREW_PREFIX + src.relative_path_from(prefix)
            return true if dst.symlink? && src == dst.resolved_path
          end
        end

        false
      end

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

        inject_file_list frameworks_found, <<~EOS
          Some frameworks can be picked up by CMake's build system and will likely
          cause the build to fail. To compile CMake, you may wish to move these
          out of the way:
        EOS
      end

      def check_tmpdir
        tmpdir = ENV.fetch("TMPDIR", nil)
        return if tmpdir.nil? || File.directory?(tmpdir)

        <<~EOS
          TMPDIR #{tmpdir.inspect} doesn't exist.
        EOS
      end

      def check_missing_deps
        return unless HOMEBREW_CELLAR.exist?

        missing = Set.new
        Homebrew::Diagnostic.missing_deps(Formula.installed).each_value do |deps|
          missing.merge(deps)
        end
        return if missing.empty?

        <<~EOS
          Some installed formulae are missing dependencies.
          You should `brew install` the missing dependencies:
            brew install #{missing.sort_by(&:full_name) * " "}

          Run `brew missing` for more details.
        EOS
      end

      def check_deprecated_disabled
        return unless HOMEBREW_CELLAR.exist?

        deprecated_or_disabled = Formula.installed.select(&:deprecated?)
        deprecated_or_disabled += Formula.installed.select(&:disabled?)
        return if deprecated_or_disabled.empty?

        <<~EOS
          Some installed formulae are deprecated or disabled.
          You should find replacements for the following formulae:
            #{deprecated_or_disabled.sort_by(&:full_name).uniq * "\n  "}
        EOS
      end

      def check_cask_deprecated_disabled
        deprecated_or_disabled = Cask::Caskroom.casks.select(&:deprecated?)
        deprecated_or_disabled += Cask::Caskroom.casks.select(&:disabled?)
        return if deprecated_or_disabled.empty?

        <<~EOS
          Some installed casks are deprecated or disabled.
          You should find replacements for the following casks:
            #{deprecated_or_disabled.sort_by(&:token).uniq * "\n  "}
        EOS
      end

      sig { returns(T.nilable(String)) }
      def check_git_status
        return unless Utils::Git.available?

        message = T.let(nil, T.nilable(String))

        repos = {
          "Homebrew/brew"          => HOMEBREW_REPOSITORY,
          "Homebrew/homebrew-core" => CoreTap.instance.path,
        }

        OFFICIAL_CASK_TAPS.each do |tap|
          cask_tap = Tap.fetch "homebrew", tap
          repos[cask_tap.full_name] = cask_tap.path if cask_tap.installed?
        end

        repos.each do |name, path|
          next unless path.exist?

          status = path.cd do
            `git status --untracked-files=all --porcelain 2>/dev/null`
          end
          next if status.blank?

          message ||= ""
          message += "\n" unless message.empty?
          message += <<~EOS
            You have uncommitted modifications to #{name}.
            If this is a surprise to you, then you should stash these modifications.
            Stashing returns Homebrew to a pristine state but can be undone
            should you later need to do so for some reason.
              cd #{path} && git stash -u && git clean -d -f
          EOS

          modified = status.split("\n")
          message += inject_file_list modified, <<~EOS

            Uncommitted files:
          EOS
        end

        message
      end

      def check_for_non_prefixed_coreutils
        coreutils = Formula["coreutils"]
        return unless coreutils.any_version_installed?

        gnubin = %W[#{coreutils.opt_libexec}/gnubin #{coreutils.libexec}/gnubin]
        return unless paths.intersect?(gnubin)

        <<~EOS
          Putting non-prefixed coreutils in your path can cause GMP builds to fail.
        EOS
      rescue FormulaUnavailableError
        nil
      end

      def check_for_pydistutils_cfg_in_home
        return unless File.exist? "#{Dir.home}/.pydistutils.cfg"

        <<~EOS
          A '.pydistutils.cfg' file was found in $HOME, which may cause Python
          builds to fail. See:
            #{Formatter.url("https://bugs.python.org/issue6138")}
            #{Formatter.url("https://bugs.python.org/issue4655")}
        EOS
      end

      def check_for_unreadable_installed_formula
        formula_unavailable_exceptions = []
        Formula.racks.each do |rack|
          Formulary.from_rack(rack)
        rescue FormulaUnreadableError, FormulaClassUnavailableError,
               TapFormulaUnreadableError, TapFormulaClassUnavailableError => e
          formula_unavailable_exceptions << e
        rescue FormulaUnavailableError, TapFormulaAmbiguityError
          nil
        end
        return if formula_unavailable_exceptions.empty?

        <<~EOS
          Some installed formulae are not readable:
            #{formula_unavailable_exceptions.join("\n\n  ")}
        EOS
      end

      def check_for_unlinked_but_not_keg_only
        unlinked = Formula.racks.reject do |rack|
          next true if (HOMEBREW_LINKED_KEGS/rack.basename).directory?

          begin
            Formulary.from_rack(rack).keg_only?
          rescue FormulaUnavailableError, TapFormulaAmbiguityError
            false
          end
        end.map(&:basename)
        return if unlinked.empty?

        inject_file_list unlinked, <<~EOS
          You have unlinked kegs in your Cellar.
          Leaving kegs unlinked can lead to build-trouble and cause formulae that depend on
          those kegs to fail to run properly once built. Run `brew link` on these:
        EOS
      end

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
          message += inject_file_list cmd_paths, <<~EOS
            Found command `#{cmd_name}` in the following places:
          EOS
        end

        message
      end

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

        bad_tap_files.keys.map do |tap|
          <<~EOS
            Found Ruby file outside #{tap} tap formula directory.
            (#{tap.formula_dir}):
              #{bad_tap_files[tap].join("\n  ")}
          EOS
        end.join("\n")
      end

      def check_homebrew_prefix
        return if Homebrew.default_prefix?

        <<~EOS
          Your Homebrew's prefix is not #{Homebrew::DEFAULT_PREFIX}.

          Many of Homebrew's bottles (binary packages) can only be used with the default prefix.
          Consider uninstalling Homebrew and reinstalling into the default prefix.
          #{please_create_pull_requests}
        EOS
      end

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

        <<~EOS
          Some installed kegs have no formulae!
          This means they were either deleted or installed manually.
          You should find replacements for the following formulae:
            #{deleted_formulae.join("\n  ")}
        EOS
      end

      def check_for_unnecessary_core_tap
        return if Homebrew::EnvConfig.developer?
        return if Homebrew::EnvConfig.no_install_from_api?
        return if Homebrew::EnvConfig.devcmdrun?
        return unless CoreTap.instance.installed?

        <<~EOS
          You have an unnecessary local Core tap!
          This can cause problems installing up-to-date formulae.
          Please remove it by running:
           brew untap #{CoreTap.instance.name}
        EOS
      end

      def check_for_unnecessary_cask_tap
        return if Homebrew::EnvConfig.developer?
        return if Homebrew::EnvConfig.no_install_from_api?
        return if Homebrew::EnvConfig.devcmdrun?

        cask_tap = CoreCaskTap.instance
        return unless cask_tap.installed?

        <<~EOS
          You have an unnecessary local Cask tap.
          This can cause problems installing up-to-date casks.
          Please remove it by running:
            brew untap #{cask_tap.name}
        EOS
      end

      def check_cask_software_versions
        add_info "Homebrew Version", HOMEBREW_VERSION
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

      def check_cask_install_location
        locations = Dir.glob(HOMEBREW_CELLAR.join("brew-cask", "*")).reverse
        return if locations.empty?

        locations.map do |l|
          "Legacy install at #{l}. Run `brew uninstall --force brew-cask`."
        end.join "\n"
      end

      def check_cask_staging_location
        # Skip this check when running CI since the staging path is not writable for security reasons
        return if GitHub::Actions.env_set?

        path = Cask::Caskroom.path

        add_info "Homebrew Cask Staging Location", user_tilde(path.to_s)

        return if !path.exist? || path.writable?

        <<~EOS
          The staging path #{user_tilde(path.to_s)} is not writable by the current user.
          To fix, run:
            sudo chown -R #{current_user} #{user_tilde(path.to_s)}
        EOS
      end

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
        add_info "Homebrew Cask Taps:", taps_info

        taps_string = Utils.pluralize("tap", error_tap_paths.count)
        "Unable to read from cask #{taps_string}: #{error_tap_paths.to_sentence}" if error_tap_paths.present?
      end

      def check_cask_load_path
        paths = $LOAD_PATH.map { user_tilde(_1) }

        add_info "$LOAD_PATHS", paths.presence || none_string

        "$LOAD_PATH is empty" if paths.blank?
      end

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

        add_info "Cask Environment Variables:", ((locale_variables + environment_variables).sort.each do |var|
          next unless ENV.key?(var)

          var = %Q(#{var}="#{ENV.fetch(var)}")
          user_tilde(var)
        end)
      end

      def check_cask_xattr
        result = system_command "/usr/bin/xattr", args: ["-h"]

        return if result.status.success?

        if result.stderr.include? "ImportError: No module named pkg_resources"
          result = Utils.popen_read "/usr/bin/python", "--version", err: :out

          if result.include? "Python 2.7"
            <<~EOS
              Your Python installation has a broken version of setuptools.
              To fix, reinstall macOS or run:
                sudo /usr/bin/python -m pip install -I setuptools
            EOS
          else
            <<~EOS
              The system Python version is wrong.
              To fix, run:
                defaults write com.apple.versioner.python Version 2.7
            EOS
          end
        elsif result.stderr.include? "pkg_resources.DistributionNotFound"
          "Your Python installation is unable to find `xattr`."
        else
          "unknown xattr error: #{result.stderr.split("\n").last}"
        end
      end

      def check_cask_quarantine_support
        case Cask::Quarantine.check_quarantine_support
        when :quarantine_available
          nil
        when :xattr_broken
          "No Cask quarantine support available: there's no working version of `xattr` on this system."
        when :no_swift
          "No Cask quarantine support available: there's no available version of `swift` on this system."
        else
          "No Cask quarantine support available: unknown reason."
        end
      end

      def non_core_taps
        @non_core_taps ||= Tap.installed.reject(&:core_tap?).reject(&:core_cask_tap?)
      end

      def check_for_duplicate_formulae
        return if ENV["HOMEBREW_TEST_BOT"].present?

        core_formula_names = CoreTap.instance.formula_names
        shadowed_formula_full_names = non_core_taps.flat_map do |tap|
          tap_formula_names = tap.formula_names.map { |s| s.delete_prefix("#{tap.name}/") }
          (core_formula_names & tap_formula_names).map { |f| "#{tap.name}/#{f}" }
        end.compact.sort
        return if shadowed_formula_full_names.empty?

        installed_formula_tap_names = Formula.installed.filter_map(&:tap).uniq.reject(&:official?).map(&:name)
        shadowed_formula_tap_names = shadowed_formula_full_names.map { |s| s.rpartition("/").first }.uniq
        unused_shadowed_formula_tap_names = (shadowed_formula_tap_names - installed_formula_tap_names).sort

        resolution = if unused_shadowed_formula_tap_names.empty?
          "Their taps are in use, so you must use these full names throughout Homebrew."
        else
          "Some of these can be resolved with:\n  brew untap #{unused_shadowed_formula_tap_names.join(" ")}"
        end

        <<~EOS
          The following formulae have the same name as core formulae:
            #{shadowed_formula_full_names.join("\n  ")}
          #{resolution}
        EOS
      end

      def check_for_duplicate_casks
        return if ENV["HOMEBREW_TEST_BOT"].present?

        core_cask_names = CoreCaskTap.instance.cask_tokens
        shadowed_cask_full_names = non_core_taps.flat_map do |tap|
          tap_cask_names = tap.cask_tokens.map { |s| s.delete_prefix("#{tap.name}/") }
          (core_cask_names & tap_cask_names).map { |f| "#{tap.name}/#{f}" }
        end.compact.sort
        return if shadowed_cask_full_names.empty?

        installed_cask_tap_names = Cask::Caskroom.casks.filter_map(&:tap).uniq.reject(&:official?).map(&:name)
        shadowed_cask_tap_names = shadowed_cask_full_names.map { |s| s.rpartition("/").first }.uniq
        unused_shadowed_cask_tap_names = (shadowed_cask_tap_names - installed_cask_tap_names).sort

        resolution = if unused_shadowed_cask_tap_names.empty?
          "Their taps are in use, so you must use these full names throughout Homebrew."
        else
          "Some of these can be resolved with:\n  brew untap #{unused_shadowed_cask_tap_names.join(" ")}"
        end

        <<~EOS
          The following casks have the same name as core casks:
            #{shadowed_cask_full_names.join("\n  ")}
          #{resolution}
        EOS
      end

      def all
        methods.map(&:to_s).grep(/^check_/).sort
      end

      def cask_checks
        all.grep(/^check_cask_/)
      end

      def current_user
        ENV.fetch("USER", "$(whoami)")
      end
    end
  end
end

require "extend/os/diagnostic"
