# typed: strict
# frozen_string_literal: true

require "env_config"
require "cask/config"

module Cask
  class Upgrade
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
        quiet:               T.nilable(T::Boolean),
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
      quiet: false,
      binaries: nil,
      quarantine: nil,
      require_sha: nil
    )
      quarantine = true if quarantine.nil?

      greedy = true if Homebrew::EnvConfig.upgrade_greedy?

      greedy_casks = if (upgrade_greedy_casks = Homebrew::EnvConfig.upgrade_greedy_casks.presence)
        upgrade_greedy_casks.split
      else
        []
      end

      outdated_casks = if casks.empty?
        Caskroom.casks(config: Config.from_args(args)).select do |cask|
          cask_greedy = greedy || greedy_casks.include?(cask.token)
          cask.outdated?(greedy: cask_greedy, greedy_latest:,
                         greedy_auto_updates:)
        end
      else
        casks.select do |cask|
          raise CaskNotInstalledError, cask if !cask.installed? && !force

          if cask.outdated?(greedy: true)
            true
          elsif cask.version.latest?
            opoo "Not upgrading #{cask.token}, the downloaded artifact has not changed" unless quiet
            false
          else
            opoo "Not upgrading #{cask.token}, the latest version is already installed" unless quiet
            false
          end
        end
      end

      manual_installer_casks = outdated_casks.select do |cask|
        cask.artifacts.any? do |artifact|
          artifact.is_a?(Artifact::Installer) && artifact.manual_install
        end
      end

      if manual_installer_casks.present?
        count = manual_installer_casks.count
        ofail "Not upgrading #{count} `installer manual` #{::Utils.pluralize("cask", count)}."
        puts manual_installer_casks.map(&:to_s)
        outdated_casks -= manual_installer_casks
      end

      return false if outdated_casks.empty?

      if casks.empty? && !greedy && greedy_casks.empty?
        if !greedy_auto_updates && !greedy_latest
          ohai "Casks with 'auto_updates true' or 'version :latest' " \
               "will not be upgraded; pass `--greedy` to upgrade them."
        end
        if greedy_auto_updates && !greedy_latest
          ohai "Casks with 'version :latest' will not be upgraded; pass `--greedy-latest` to upgrade them."
        end
        if !greedy_auto_updates && greedy_latest
          ohai "Casks with 'auto_updates true' will not be upgraded; pass `--greedy-auto-updates` to upgrade them."
        end
      end

      verb = dry_run ? "Would upgrade" : "Upgrading"
      oh1 "#{verb} #{outdated_casks.count} outdated #{::Utils.pluralize("package", outdated_casks.count)}:"

      caught_exceptions = []

      upgradable_casks = outdated_casks.map do |c|
        unless c.installed?
          odie <<~EOS
            The cask '#{c.token}' was affected by a bug and cannot be upgraded as-is. To fix this, run:
              brew reinstall --cask --force #{c.token}
          EOS
        end

        [CaskLoader.load(c.installed_caskfile), c]
      end

      puts upgradable_casks
        .map { |(old_cask, new_cask)| "#{new_cask.full_name} #{old_cask.version} -> #{new_cask.version}" }
        .join("\n")
      return true if dry_run

      upgradable_casks.each do |(old_cask, new_cask)|
        upgrade_cask(
          old_cask, new_cask,
          binaries:, force:, skip_cask_deps:, verbose:,
          quarantine:, require_sha:
        )
      rescue => e
        new_exception = e.exception("#{new_cask.full_name}: #{e}")
        new_exception.set_backtrace(e.backtrace)
        caught_exceptions << new_exception
        next
      end

      return true if caught_exceptions.empty?
      raise MultipleCaskErrors, caught_exceptions if caught_exceptions.count > 1
      raise caught_exceptions.fetch(0) if caught_exceptions.count == 1

      false
    end

    sig {
      params(
        old_cask:       Cask,
        new_cask:       Cask,
        binaries:       T.nilable(T::Boolean),
        force:          T.nilable(T::Boolean),
        quarantine:     T.nilable(T::Boolean),
        require_sha:    T.nilable(T::Boolean),
        skip_cask_deps: T.nilable(T::Boolean),
        verbose:        T.nilable(T::Boolean),
      ).void
    }
    def self.upgrade_cask(
      old_cask, new_cask,
      binaries:, force:, quarantine:, require_sha:, skip_cask_deps:, verbose:
    )
      require "cask/installer"

      start_time = Time.now
      odebug "Started upgrade process for Cask #{old_cask}"
      old_config = old_cask.config

      old_options = {
        binaries:,
        verbose:,
        force:,
        upgrade:  true,
      }.compact

      old_cask_installer =
        Installer.new(old_cask, **old_options)

      new_cask.config = new_cask.default_config.merge(old_config)

      new_options = {
        binaries:,
        verbose:,
        force:,
        skip_cask_deps:,
        require_sha:,
        upgrade:        true,
        quarantine:,
      }.compact

      new_cask_installer =
        Installer.new(new_cask, **new_options)

      started_upgrade = false
      new_artifacts_installed = false

      begin
        oh1 "Upgrading #{Formatter.identifier(old_cask)}"

        # Start new cask's installation steps
        new_cask_installer.check_conflicts

        if (caveats = new_cask_installer.caveats)
          puts caveats
        end

        new_cask_installer.fetch

        # Move the old cask's artifacts back to staging
        old_cask_installer.start_upgrade(successor: new_cask)
        # And flag it so in case of error
        started_upgrade = true

        # Install the new cask
        new_cask_installer.stage

        new_cask_installer.install_artifacts(predecessor: old_cask)
        new_artifacts_installed = true

        # If successful, wipe the old cask from staging.
        old_cask_installer.finalize_upgrade
      rescue => e
        new_cask_installer.uninstall_artifacts(successor: old_cask) if new_artifacts_installed
        new_cask_installer.purge_versioned_files
        old_cask_installer.revert_upgrade(predecessor: new_cask) if started_upgrade
        raise e
      end

      end_time = Time.now
      Homebrew.messages.package_installed(new_cask.token, end_time - start_time)
    end
  end
end
