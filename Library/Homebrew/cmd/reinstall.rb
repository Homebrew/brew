# typed: true
# frozen_string_literal: true

require "formula_installer"
require "development_tools"
require "messages"
require "install"
require "reinstall"
require "cli/parser"
require "cleanup"
require "cask/utils"
require "cask/macos"
require "cask/reinstall"
require "upgrade"
require "api"

module Homebrew
  sig { returns(CLI::Parser) }
  def self.reinstall_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Uninstall and then reinstall a <formula> or <cask> using the same options it was
        originally installed with, plus any appended options specific to a <formula>.

        Unless `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew reinstall` will be run for
        outdated dependents and dependents with broken linkage, respectively.

        Unless `HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run for the
        reinstalled formulae or, every 30 days, for all formulae.
      EOS
      switch "-d", "--debug",
             description: "If brewing fails, open an interactive debugging session with access to IRB " \
                          "or a shell inside the temporary build directory."
      switch "-f", "--force",
             description: "Install without checking for previously installed keg-only or " \
                          "non-migrated versions."
      switch "-v", "--verbose",
             description: "Print the verification and post-install steps."
      [
        [:switch, "--formula", "--formulae", { description: "Treat all named arguments as formulae." }],
        [:switch, "-s", "--build-from-source", {
          description: "Compile <formula> from source even if a bottle is available.",
        }],
        [:switch, "-i", "--interactive", {
          description: "Download and patch <formula>, then open a shell. This allows the user to " \
                       "run `./configure --help` and otherwise determine how to turn the software " \
                       "package into a Homebrew package.",
        }],
        [:switch, "--force-bottle", {
          description: "Install from a bottle if it exists for the current or newest version of " \
                       "macOS, even if it would not normally be used for installation.",
        }],
        [:switch, "--keep-tmp", {
          description: "Retain the temporary files created during installation.",
        }],
        [:switch, "--debug-symbols", {
          depends_on:  "--build-from-source",
          description: "Generate debug symbols on build. Source will be retained in a cache directory.",
        }],
        [:switch, "--display-times", {
          env:         :display_install_times,
          description: "Print install times for each formula at the end of the run.",
        }],
        [:switch, "-g", "--git", {
          description: "Create a Git repository, useful for creating patches to the software.",
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

      conflicts "--build-from-source", "--force-bottle"

      named_args [:formula, :cask], min: 1
    end
  end

  def self.reinstall
    args = reinstall_args.parse

    formulae, casks = args.named.to_formulae_and_casks(method: :resolve)
                          .partition { |o| o.is_a?(Formula) }

    if args.build_from_source?
      unless DevelopmentTools.installed?
        raise BuildFlagsError.new(["--build-from-source"], bottled: formulae.all?(&:bottled?))
      end

      unless Homebrew::EnvConfig.developer?
        opoo "building from source is not supported!"
        puts "You're on your own. Failures are expected so don't create any issues, please!"
      end
    end

    Install.perform_preinstall_checks

    formulae.each do |formula|
      if formula.pinned?
        onoe "#{formula.full_name} is pinned. You must unpin it to reinstall."
        next
      end
      Migrator.migrate_if_needed(formula, force: args.force?)
      reinstall_formula(
        formula,
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
        git:                        args.git?,
      )
      Cleanup.install_formula_clean!(formula)
    end

    Upgrade.check_installed_dependents(
      formulae,
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
    )

    if casks.any?
      Cask::Reinstall.reinstall_casks(
        *casks,
        binaries:       args.binaries?,
        verbose:        args.verbose?,
        force:          args.force?,
        require_sha:    args.require_sha?,
        skip_cask_deps: args.skip_cask_deps?,
        quarantine:     args.quarantine?,
        zap:            args.zap?,
      )
    end

    Cleanup.periodic_clean!

    Homebrew.messages.display_messages(display_times: args.display_times?)
  end
end
