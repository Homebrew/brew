# typed: false
# frozen_string_literal: true

require "env_config"
require "cask/config"

module Cask
  class Cmd
    # Cask implementation of the `brew upgrade` command.
    #
    # @api private
    class Upgrade < AbstractCommand
      extend T::Sig

      OPTIONS = [
        [:switch, "--skip-cask-deps", {
          description: "Skip installing cask dependencies.",
        }],
        [:switch, "--greedy", {
          description: "Also include casks with `auto_updates true` or `version :latest`.",
        }],
        [:switch, "--greedy-latest", {
          description: "Also include casks with `version :latest`.",
        }],
        [:switch, "--greedy-auto-updates", {
          description: "Also include casks with `auto_updates true`.",
        }],
      ].freeze

      sig { returns(Homebrew::CLI::Parser) }
      def self.parser
        super do
          switch "--force",
                 description: "Force overwriting existing files."
          switch "--dry-run",
                 description: "Show what would be upgraded, but do not actually upgrade anything."

          OPTIONS.each do |option|
            send(*option)
          end
        end
      end

      sig { void }
      def run
        verbose = ($stdout.tty? || args.verbose?) && !args.quiet?
        self.class.upgrade_casks(
          *casks,
          force:               args.force?,
          greedy:              args.greedy?,
          greedy_latest:       args.greedy_latest?,
          greedy_auto_updates: args.greedy_auto_updates?,
          dry_run:             args.dry_run?,
          binaries:            args.binaries?,
          quarantine:          args.quarantine?,
          require_sha:         args.require_sha?,
          skip_cask_deps:      args.skip_cask_deps?,
          verbose:             verbose,
          args:                args,
        )
      end

      sig {
        params(
          casks:               Cask,
          args:                Homebrew::CLI::Args,
          force:               T.nilable(T::Boolean),
          greedy:              T.nilable(T::Boolean),
          greedy_latest:       T.nilable(T::Boolean),
          greedy_auto_updates: T.nilable(T::Boolean),
          dry_run:             T.nilable(T::Boolean),
          skip_cask_deps:      T.nilable(T::Boolean),
          verbose:             T.nilable(T::Boolean),
          binaries:            T.nilable(T::Boolean),
          quarantine:          T.nilable(T::Boolean),
          require_sha:         T.nilable(T::Boolean),
        ).returns(T::Boolean)
      }
      def self.upgrade_casks(
        *casks,
        args:,
        force: false,
        greedy: false,
        greedy_latest: false,
        greedy_auto_updates: false,
        dry_run: false,
        skip_cask_deps: false,
        verbose: false,
        binaries: nil,
        quarantine: nil,
        require_sha: nil
      )

        quarantine = true if quarantine.nil?

        outdated_casks = if casks.empty?
          Caskroom.casks(config: Config.from_args(args)).select do |cask|
            cask.outdated?(greedy: greedy, greedy_latest: args.greedy_latest?,
                           greedy_auto_updates: args.greedy_auto_updates?)
          end
        else
          casks.select do |cask|
            raise CaskNotInstalledError, cask if !cask.installed? && !force

            cask.outdated?(greedy: true)
          end
        end

        manual_installer_casks = outdated_casks.select do |cask|
          cask.artifacts.any?(Artifact::Installer::ManualInstaller)
        end

        if manual_installer_casks.present?
          count = manual_installer_casks.count
          ofail "Not upgrading #{count} `installer manual` #{"cask".pluralize(count)}."
          puts manual_installer_casks.map(&:to_s)
          outdated_casks -= manual_installer_casks
        end

        return false if outdated_casks.empty?

        if casks.empty? && !greedy
          if !args.greedy_auto_updates? && !args.greedy_latest?
            ohai "Casks with 'auto_updates true' or 'version :latest'
            will not be upgraded; pass `--greedy` to upgrade them."
          end
          if args.greedy_auto_updates? && !args.greedy_latest?
            ohai "Casks with 'version :latest' will not be upgraded; pass `--greedy-latest` to upgrade them."
          end
          if !args.greedy_auto_updates? && args.greedy_latest?
            ohai "Casks with 'auto_updates true' will not be upgraded; pass `--greedy-auto-updates` to upgrade them."
          end
        end

        verb = dry_run ? "Would upgrade" : "Upgrading"
        oh1 "#{verb} #{outdated_casks.count} #{"outdated package".pluralize(outdated_casks.count)}:"

        caught_exceptions = []

        upgradable_casks = outdated_casks.map { |c| [CaskLoader.load(c.installed_caskfile), c] }

        puts upgradable_casks
          .map { |(old_cask, new_cask)| "#{new_cask.full_name} #{old_cask.version} -> #{new_cask.version}" }
          .join("\n")
        return true if dry_run

        upgradable_casks.each do |(old_cask, new_cask)|
          upgrade_cask(
            old_cask, new_cask,
            binaries: binaries, force: force, skip_cask_deps: skip_cask_deps, verbose: verbose,
            quarantine: quarantine, require_sha: require_sha
          )
        rescue => e
          caught_exceptions << e.exception("#{new_cask.full_name}: #{e}")
          next
        end

        return true if caught_exceptions.empty?
        raise MultipleCaskErrors, caught_exceptions if caught_exceptions.count > 1
        raise caught_exceptions.first if caught_exceptions.count == 1
      end

      def self.upgrade_cask(
        old_cask, new_cask,
        binaries:, force:, quarantine:, require_sha:, skip_cask_deps:, verbose:
      )
        require "cask/installer"

        odebug "Started upgrade process for Cask #{old_cask}"
        old_config = old_cask.config

        old_options = {
          binaries: binaries,
          verbose:  verbose,
          force:    force,
          upgrade:  true,
        }.compact

        old_cask_installer =
          Installer.new(old_cask, **old_options)

        new_cask.config = new_cask.default_config.merge(old_config)

        new_options = {
          binaries:       binaries,
          verbose:        verbose,
          force:          force,
          skip_cask_deps: skip_cask_deps,
          require_sha:    require_sha,
          upgrade:        true,
          quarantine:     quarantine,
        }.compact

        new_cask_installer =
          Installer.new(new_cask, **new_options)

        started_upgrade = false
        new_artifacts_installed = false

        begin
          oh1 "Upgrading #{Formatter.identifier(old_cask)}"

          # Start new cask's installation steps
          new_cask_installer.check_conflicts

          puts new_cask_installer.caveats if new_cask_installer.caveats

          new_cask_installer.fetch

          # Move the old cask's artifacts back to staging
          old_cask_installer.start_upgrade
          # And flag it so in case of error
          started_upgrade = true

          # Install the new cask
          new_cask_installer.stage

          new_cask_installer.install_artifacts
          new_artifacts_installed = true

          # If successful, wipe the old cask from staging
          old_cask_installer.finalize_upgrade
        rescue => e
          new_cask_installer.uninstall_artifacts if new_artifacts_installed
          new_cask_installer.purge_versioned_files
          old_cask_installer.revert_upgrade if started_upgrade
          raise e
        end
      end
    end
  end
end
