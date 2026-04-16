# typed: strict
# frozen_string_literal: true

require "env_config"
require "cask/config"
require "deprecate_disable"
require "utils/output"

module Cask
  class Upgrade
    extend ::Utils::Output::Mixin

    sig { returns(T::Array[String]) }
    def self.greedy_casks
      if (upgrade_greedy_casks = Homebrew::EnvConfig.upgrade_greedy_casks.presence)
        upgrade_greedy_casks.split
      else
        []
      end
    end

    sig {
      params(
        casks:               T::Array[Cask],
        args:                Homebrew::CLI::Args,
        force:               T.nilable(T::Boolean),
        quiet:               T.nilable(T::Boolean),
        greedy:              T.nilable(T::Boolean),
        greedy_latest:       T.nilable(T::Boolean),
        greedy_auto_updates: T.nilable(T::Boolean),
      ).returns(T::Array[Cask])
    }
    def self.outdated_casks(casks, args:, force:, quiet:,
                            greedy: false, greedy_latest: false, greedy_auto_updates: false)
      # Validate mutually exclusive opt-in/opt-out env vars before we start
      # selecting casks so `brew upgrade` errors consistently.
      Homebrew::EnvConfig.upgrade_auto_updates_casks?
      greedy = true if Homebrew::EnvConfig.upgrade_greedy?

      if casks.empty?
        Caskroom.casks(config: Config.from_args(args)).select do |cask|
          if cask.disabled?
            opoo "Not upgrading #{cask.token}, it is #{DeprecateDisable.message(cask)}" unless quiet
            next false
          end

          cask_greedy = greedy || greedy_casks.include?(cask.token)
          cask.outdated?(greedy: cask_greedy, greedy_latest:,
                         greedy_auto_updates:)
        end
      else
        casks.select do |cask|
          raise CaskNotInstalledError, cask if !cask.installed? && !force

          if cask.disabled?
            opoo "Not upgrading #{cask.token}, it is #{DeprecateDisable.message(cask)}" unless quiet
            next false
          end

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
    end

    sig { params(cask_upgrades: T::Array[String], dry_run: T.nilable(T::Boolean)).void }
    def self.show_upgrade_summary(cask_upgrades, dry_run: false)
      return if cask_upgrades.empty?

      verb = dry_run ? "Would upgrade" : "Upgrading"
      oh1 "#{verb} #{cask_upgrades.count} outdated #{::Utils.pluralize("package", cask_upgrades.count)}:"
      puts cask_upgrades.join("\n")
    end

    sig {
      params(
        casks:                Cask,
        args:                 Homebrew::CLI::Args,
        force:                T.nilable(T::Boolean),
        greedy:               T.nilable(T::Boolean),
        greedy_latest:        T.nilable(T::Boolean),
        greedy_auto_updates:  T.nilable(T::Boolean),
        dry_run:              T.nilable(T::Boolean),
        skip_cask_deps:       T.nilable(T::Boolean),
        verbose:              T.nilable(T::Boolean),
        quiet:                T.nilable(T::Boolean),
        binaries:             T.nilable(T::Boolean),
        quarantine:           T.nilable(T::Boolean),
        require_sha:          T.nilable(T::Boolean),
        skip_prefetch:        T::Boolean,
        show_upgrade_summary: T::Boolean,
        download_queue:       T.nilable(Homebrew::DownloadQueue),
      ).returns(T::Boolean)
    }
    def self.upgrade_casks!(
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
      require_sha: nil,
      skip_prefetch: false,
      show_upgrade_summary: true,
      download_queue: nil
    )
      quarantine = true if quarantine.nil?

      outdated_casks =
        self.outdated_casks(casks, args:, greedy:, greedy_latest:, greedy_auto_updates:, force:, quiet:)

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

      if !Homebrew::EnvConfig.no_env_hints? && casks.empty? && !greedy && greedy_casks.empty?
        output_hint = false
        if !greedy_auto_updates && outdated_casks.any?(&:auto_updates)
          puts "Homebrew will now attempt to upgrade casks with `auto_updates true`."
          puts "Disable this behaviour with `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1`."
          output_hint ||= true
        end
        if !greedy_auto_updates && !greedy_latest
          puts "Some casks with `auto_updates true` or `version :latest` may still require `--greedy`,"
          puts "`HOMEBREW_UPGRADE_GREEDY` or `HOMEBREW_UPGRADE_GREEDY_CASKS` to be upgraded."
          output_hint ||= true
        end
        if greedy_auto_updates && !greedy_latest
          puts "Casks with `version :latest` will not be upgraded; pass `--greedy-latest` to upgrade them."
          output_hint ||= true
        end
        if !greedy_auto_updates && greedy_latest
          puts "Some casks with `auto_updates true` may still require `--greedy-auto-updates` to be upgraded."
          output_hint ||= true
        end
        puts "Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`)." if output_hint
      end

      upgradable_casks = outdated_casks.filter_map do |c|
        invalid_cask = !c.installed?

        invalid_cask ||= begin
          loaded_cask = CaskLoader.load(T.must(c.installed_caskfile))
          false
        rescue CaskInvalidError, CaskUnavailableError
          true
        end

        if invalid_cask
          opoo <<~EOS
            The cask '#{c.token}' cannot be upgraded as-is. To fix this, run:
            brew reinstall --cask --force #{c.token}
          EOS
          next
        end

        [loaded_cask, c]
      end

      return false if upgradable_casks.empty?

      cask_upgrades = upgradable_casks.map do |(old_cask, new_cask)|
        "#{new_cask.full_name} #{old_cask.version} -> #{new_cask.version}"
      end

      created_download_queue = T.let(false, T::Boolean)
      download_queue ||= if !dry_run && !skip_prefetch
        created_download_queue = true
        Homebrew::DownloadQueue.new(pour: true)
      end

      if !dry_run && !skip_prefetch
        prefetch_download_queue = download_queue || Homebrew.default_download_queue
        begin
          fetchable_casks = upgradable_casks.map(&:last)
          fetchable_cask_installers = fetchable_casks.map do |cask|
            # This is significantly easier given the weird difference in Sorbet signatures here.
            # rubocop:disable Style/DoubleNegation
            Installer.new(cask, binaries: !!binaries, verbose: !!verbose, force: !!force,
                                                 skip_cask_deps: !!skip_cask_deps, require_sha: !!require_sha,
                                                 upgrade: true, quarantine:, download_queue: prefetch_download_queue,
                                                 defer_fetch: true)
            # rubocop:enable Style/DoubleNegation
          end

          fetchable_cask_installers.each(&:prelude)

          fetchable_casks_sentence = fetchable_casks.map { |cask| Formatter.identifier(cask.full_name) }.to_sentence
          oh1 "Fetching downloads for: #{fetchable_casks_sentence}", truncate: false

          fetchable_cask_installers.each(&:enqueue_downloads)
          prefetch_download_queue.fetch
        ensure
          prefetch_download_queue.shutdown if created_download_queue
        end
      end

      show_upgrade_summary(cask_upgrades, dry_run:) if show_upgrade_summary
      return true if dry_run

      caught_exceptions = []

      download_queue ||= Homebrew.default_download_queue

      upgradable_casks.each do |(old_cask, new_cask)|
        upgrade_cask(
          old_cask, new_cask,
          binaries:, force:, skip_cask_deps:, verbose:,
          quarantine:, require_sha:, download_queue:
        )
      rescue => e
        new_exception = e.exception("#{new_cask.full_name}: #{e}")
        new_exception.set_backtrace(e.backtrace)
        caught_exceptions << new_exception
        next
      end

      return true if caught_exceptions.empty?
      raise MultipleCaskErrors, caught_exceptions if caught_exceptions.count > 1
      raise caught_exceptions.fetch(0) if caught_exceptions.one?

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
        download_queue: Homebrew::DownloadQueue,
      ).void
    }
    def self.upgrade_cask(
      old_cask, new_cask,
      binaries:, force:, quarantine:, require_sha:, skip_cask_deps:, verbose:, download_queue:
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
        download_queue:,
        defer_fetch:    true,
      }.compact

      new_cask_installer =
        Installer.new(new_cask, **new_options)

      started_upgrade = false
      new_artifacts_installed = false

      begin
        oh1 "Upgrading #{Formatter.identifier(old_cask)}"
        puts "  #{old_cask.version} -> #{new_cask.version}"

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
