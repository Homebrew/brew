# typed: true
# frozen_string_literal: true

require "cask/config"
require "cask/installer"
require "cask_dependent"
require "missing_formula"
require "formula_installer"
require "development_tools"
require "install"
require "cleanup"
require "cli/parser"
require "upgrade"

module Homebrew
  sig { returns(CLI::Parser) }
  def self.install_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Install a <formula> or <cask>. Additional options specific to a <formula> may be
        appended to the command.

        Unless `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew reinstall` will be run for
        outdated dependents and dependents with broken linkage, respectively.

        Unless `HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run for
        the installed formulae or, every 30 days, for all formulae.

        Unless `HOMEBREW_NO_INSTALL_UPGRADE` is set, `brew install` <formula> will upgrade <formula> if it
        is already installed but outdated.
      EOS
      switch "-d", "--debug",
             description: "If brewing fails, open an interactive debugging session with access to IRB " \
                          "or a shell inside the temporary build directory."
      switch "-f", "--force",
             description: "Install formulae without checking for previously installed keg-only or " \
                          "non-migrated versions. When installing casks, overwrite existing files " \
                          "(binaries and symlinks are excluded, unless originally from the same cask)."
      switch "-v", "--verbose",
             description: "Print the verification and post-install steps."
      switch "-n", "--dry-run",
             description: "Show what would be installed, but do not actually install anything."
      [
        [:switch, "--formula", "--formulae", {
          description: "Treat all named arguments as formulae.",
        }],
        [:flag, "--env=", {
          description: "Disabled other than for internal Homebrew use.",
          hidden:      true,
        }],
        [:switch, "--ignore-dependencies", {
          description: "An unsupported Homebrew development option to skip installing any dependencies of any " \
                       "kind. If the dependencies are not already present, the formula will have issues. If you're " \
                       "not developing Homebrew, consider adjusting your PATH rather than using this option.",
        }],
        [:switch, "--only-dependencies", {
          description: "Install the dependencies with specified options but do not install the " \
                       "formula itself.",
        }],
        [:flag, "--cc=", {
          description: "Attempt to compile using the specified <compiler>, which should be the name of the " \
                       "compiler's executable, e.g. `gcc-7` for GCC 7. In order to use LLVM's clang, specify " \
                       "`llvm_clang`. To use the Apple-provided clang, specify `clang`. This option will only " \
                       "accept compilers that are provided by Homebrew or bundled with macOS. Please do not " \
                       "file issues if you encounter errors while using this option.",
        }],
        [:switch, "-s", "--build-from-source", {
          description: "Compile <formula> from source even if a bottle is provided. " \
                       "Dependencies will still be installed from bottles if they are available.",
        }],
        [:switch, "--force-bottle", {
          description: "Install from a bottle if it exists for the current or newest version of " \
                       "macOS, even if it would not normally be used for installation.",
        }],
        [:switch, "--include-test", {
          description: "Install testing dependencies required to run `brew test` <formula>.",
        }],
        [:switch, "--HEAD", {
          description: "If <formula> defines it, install the HEAD version, aka. main, trunk, unstable, master.",
        }],
        [:switch, "--fetch-HEAD", {
          description: "Fetch the upstream repository to detect if the HEAD installation of the " \
                       "formula is outdated. Otherwise, the repository's HEAD will only be checked for " \
                       "updates when a new stable or development version has been released.",
        }],
        [:switch, "--keep-tmp", {
          description: "Retain the temporary files created during installation.",
        }],
        [:switch, "--debug-symbols", {
          depends_on:  "--build-from-source",
          description: "Generate debug symbols on build. Source will be retained in a cache directory.",
        }],
        [:switch, "--build-bottle", {
          description: "Prepare the formula for eventual bottling during installation, skipping any " \
                       "post-install steps.",
        }],
        [:switch, "--skip-post-install", {
          description: "Install but skip any post-install steps.",
        }],
        [:flag, "--bottle-arch=", {
          depends_on:  "--build-bottle",
          description: "Optimise bottles for the specified architecture rather than the oldest " \
                       "architecture supported by the version of macOS the bottles are built on.",
        }],
        [:switch, "--display-times", {
          env:         :display_install_times,
          description: "Print install times for each package at the end of the run.",
        }],
        [:switch, "-i", "--interactive", {
          description: "Download and patch <formula>, then open a shell. This allows the user to " \
                       "run `./configure --help` and otherwise determine how to turn the software " \
                       "package into a Homebrew package.",
        }],
        [:switch, "-g", "--git", {
          description: "Create a Git repository, useful for creating patches to the software.",
        }],
        [:switch, "--overwrite", {
          description: "Delete files that already exist in the prefix while linking.",
        }],
      ].each do |args|
        options = args.pop
        send(*args, **options)
        conflicts "--cask", args.last
      end
      formula_options
      [
        [:switch, "--cask", "--casks", { description: "Treat all named arguments as casks." }],
        [:switch, "--[no-]binaries", {
          description: "Disable/enable linking of helper executables (default: enabled).",
          env:         :cask_opts_binaries,
        }],
        [:switch, "--require-sha",  {
          description: "Require all casks to have a checksum.",
          env:         :cask_opts_require_sha,
        }],
        [:switch, "--[no-]quarantine", {
          description: "Disable/enable quarantining of downloads (default: enabled).",
          env:         :cask_opts_quarantine,
        }],
        [:switch, "--adopt", {
          description: "Adopt existing artifacts in the destination that are identical to those being installed. " \
                       "Cannot be combined with --force.",
        }],
        [:switch, "--skip-cask-deps", {
          description: "Skip installing cask dependencies.",
        }],
        [:switch, "--zap", {
          description: "For use with `brew reinstall --cask`. Remove all files associated with a cask. " \
                       "*May remove files which are shared between applications.*",
        }],
      ].each do |args|
        options = args.pop
        send(*args, **options)
        conflicts "--formula", args.last
      end
      cask_options

      conflicts "--ignore-dependencies", "--only-dependencies"
      conflicts "--build-from-source", "--build-bottle", "--force-bottle"
      conflicts "--adopt", "--force"

      named_args [:formula, :cask], min: 1
    end
  end

  def self.install
    args = install_args.parse

    if args.env.present?
      # Can't use `replacement: false` because `install_args` are used by
      # `build.rb`. Instead, `hide_from_man_page` and don't do anything with
      # this argument here.
      # This odisabled should stick around indefinitely.
      odisabled "brew install --env", "`env :std` in specific formula files"
    end

    args.named.each do |name|
      next if File.exist?(name)
      next unless name =~ HOMEBREW_TAP_FORMULA_REGEX

      tap = Tap.fetch(Regexp.last_match(1), Regexp.last_match(2))
      tap.ensure_installed!
    end

    if args.ignore_dependencies?
      opoo <<~EOS
        #{Tty.bold}`--ignore-dependencies` is an unsupported Homebrew developer option!#{Tty.reset}
        Adjust your PATH to put any preferred versions of applications earlier in the
        PATH rather than using this unsupported option!

      EOS
    end

    begin
      formulae, casks = args.named.to_formulae_and_casks
                            .partition { |formula_or_cask| formula_or_cask.is_a?(Formula) }
    rescue FormulaOrCaskUnavailableError, Cask::CaskUnavailableError
      cask_tap = CoreCaskTap.instance
      if !cask_tap.installed? && (args.cask? || Tap.untapped_official_taps.exclude?(cask_tap.name))
        cask_tap.ensure_installed!
        retry if cask_tap.installed?
      end

      raise
    end

    if casks.any?

      if args.dry_run?
        if (casks_to_install = casks.reject(&:installed?).presence)
          ohai "Would install #{::Utils.pluralize("cask", casks_to_install.count, include_count: true)}:"
          puts casks_to_install.map(&:full_name).join(" ")
        end
        casks.each do |cask|
          dep_names = CaskDependent.new(cask)
                                   .runtime_dependencies
                                   .reject(&:installed?)
                                   .map(&:to_formula)
                                   .map(&:name)
          next if dep_names.blank?

          ohai "Would install #{::Utils.pluralize("dependenc", dep_names.count, plural: "ies", singular: "y",
                                                  include_count: true)} for #{cask.full_name}:"
          puts dep_names.join(" ")
        end
        return
      end

      require "cask/installer"

      installed_casks, new_casks = casks.partition(&:installed?)

      new_casks.each do |cask|
        Cask::Installer.new(
          cask,
          binaries:       args.binaries?,
          verbose:        args.verbose?,
          force:          args.force?,
          adopt:          args.adopt?,
          require_sha:    args.require_sha?,
          skip_cask_deps: args.skip_cask_deps?,
          quarantine:     args.quarantine?,
          quiet:          args.quiet?,
        ).install
      end

      if !Homebrew::EnvConfig.no_install_upgrade? && installed_casks.any?
        require "cask/upgrade"

        Cask::Upgrade.upgrade_casks(
          *installed_casks,
          force:          args.force?,
          dry_run:        args.dry_run?,
          binaries:       args.binaries?,
          quarantine:     args.quarantine?,
          require_sha:    args.require_sha?,
          skip_cask_deps: args.skip_cask_deps?,
          verbose:        args.verbose?,
          args:           args,
        )
      end
    end

    # if the user's flags will prevent bottle only-installations when no
    # developer tools are available, we need to stop them early on
    build_flags = []
    unless DevelopmentTools.installed?
      build_flags << "--HEAD" if args.HEAD?
      build_flags << "--build-bottle" if args.build_bottle?
      build_flags << "--build-from-source" if args.build_from_source?

      raise BuildFlagsError.new(build_flags, bottled: formulae.all?(&:bottled?)) if build_flags.present?
    end

    if build_flags.present? && !Homebrew::EnvConfig.developer?
      opoo "building from source is not supported!"
      puts "You're on your own. Failures are expected so don't create any issues, please!"
    end

    installed_formulae = formulae.select do |f|
      Install.install_formula?(
        f,
        head:              args.HEAD?,
        fetch_head:        args.fetch_HEAD?,
        only_dependencies: args.only_dependencies?,
        force:             args.force?,
        quiet:             args.quiet?,
      )
    end

    return if installed_formulae.empty?

    Install.perform_preinstall_checks(cc: args.cc)

    Install.install_formulae(
      installed_formulae,
      build_bottle:               args.build_bottle?,
      force_bottle:               args.force_bottle?,
      bottle_arch:                args.bottle_arch,
      ignore_deps:                args.ignore_dependencies?,
      only_deps:                  args.only_dependencies?,
      include_test_formulae:      args.include_test_formulae,
      build_from_source_formulae: args.build_from_source_formulae,
      cc:                         args.cc,
      git:                        args.git?,
      interactive:                args.interactive?,
      keep_tmp:                   args.keep_tmp?,
      debug_symbols:              args.debug_symbols?,
      force:                      args.force?,
      overwrite:                  args.overwrite?,
      debug:                      args.debug?,
      quiet:                      args.quiet?,
      verbose:                    args.verbose?,
      dry_run:                    args.dry_run?,
      skip_post_install:          args.skip_post_install?,
    )

    Upgrade.check_installed_dependents(
      installed_formulae,
      flags:                      args.flags_only,
      installed_on_request:       args.named.present?,
      force_bottle:               args.force_bottle?,
      build_from_source_formulae: args.build_from_source_formulae,
      interactive:                args.interactive?,
      keep_tmp:                   args.keep_tmp?,
      debug_symbols:              args.debug_symbols?,
      force:                      args.force?,
      debug:                      args.debug?,
      quiet:                      args.quiet?,
      verbose:                    args.verbose?,
      dry_run:                    args.dry_run?,
    )

    Cleanup.periodic_clean!(dry_run: args.dry_run?)

    Homebrew.messages.display_messages(display_times: args.display_times?)
  rescue FormulaUnreadableError, FormulaClassUnavailableError,
         TapFormulaUnreadableError, TapFormulaClassUnavailableError => e
    # Need to rescue before `FormulaUnavailableError` (superclass of this)
    # is handled, as searching for a formula doesn't make sense here (the
    # formula was found, but there's a problem with its implementation).
    $stderr.puts Utils::Backtrace.clean(e) if Homebrew::EnvConfig.developer?
    ofail e.message
  rescue FormulaOrCaskUnavailableError, Cask::CaskUnavailableError => e
    Homebrew.failed = true

    # formula name or cask token
    name = case e
    when FormulaOrCaskUnavailableError then e.name
    when Cask::CaskUnavailableError then e.token
    else T.absurd(e)
    end

    if name == "updog"
      ofail "What's updog?"
      return
    end

    opoo e

    reason = MissingFormula.reason(name, silent: true)
    if !args.cask? && reason
      $stderr.puts reason
      return
    end

    # We don't seem to get good search results when the tap is specified
    # so we might as well return early.
    return if name.include?("/")

    require "search"

    package_types = []
    package_types << "formulae" unless args.cask?
    package_types << "casks" unless args.formula?

    ohai "Searching for similarly named #{package_types.join(" and ")}..."

    # Don't treat formula/cask name as a regex
    string_or_regex = name
    all_formulae, all_casks = Search.search_names(string_or_regex, args)

    if all_formulae.any?
      ohai "Formulae", Formatter.columns(all_formulae)
      first_formula = all_formulae.first.to_s
      puts <<~EOS

        To install #{first_formula}, run:
          brew install #{first_formula}
      EOS
    end
    puts if all_formulae.any? && all_casks.any?
    if all_casks.any?
      ohai "Casks", Formatter.columns(all_casks)
      first_cask = all_casks.first.to_s
      puts <<~EOS

        To install #{first_cask}, run:
          brew install --cask #{first_cask}
      EOS
    end
    return if all_formulae.any? || all_casks.any?

    odie "No #{package_types.join(" or ")} found for #{name}."
  end
end
