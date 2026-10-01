# typed: strict
# frozen_string_literal: true

require "env_config"
require "cask/config"
require "cask/quarantine"
require "deprecate_disable"
require "install"
require "upgrade"
require "utils/output"
require "cask/installer"

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
        summary_pinned:      T.nilable(T::Array[String]),
        summary_disabled:    T.nilable(T::Array[String]),
      ).returns(T::Array[Cask])
    }
    def self.outdated_casks(casks, args:, force:, quiet:,
                            greedy: false, greedy_latest: false, greedy_auto_updates: false,
                            summary_pinned: nil, summary_disabled: nil)
      greedy = true if Homebrew::EnvConfig.upgrade_greedy?

      outdated_casks = if casks.empty?
        Caskroom.casks(config: Config.from_args(args)).select do |cask|
          if cask.disabled?
            summary_disabled&.push(cask.full_name)
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
            summary_disabled&.push(cask.full_name)
            opoo "Not upgrading #{cask.token}, it is #{DeprecateDisable.message(cask)}" unless quiet
            next false
          end

          version = cask.version
          if version.nil?
            opoo "Not upgrading #{cask.token}, no version is available for the current platform" unless quiet
            false
          elsif cask.outdated?(greedy: true)
            true
          elsif version.latest?
            opoo "Not upgrading #{cask.token}, the downloaded artifact has not changed" unless quiet
            false
          else
            opoo "Not upgrading #{cask.token}, the latest version is already installed" unless quiet
            false
          end
        end
      end

      pinned_casks = outdated_casks.select(&:pinned?)
      outdated_casks -= pinned_casks
      pinned_versions = pinned_casks.map do |cask|
        "#{cask.full_name} #{cask.installed_version} -> #{cask.version}"
      end
      summary_pinned&.concat(pinned_versions)

      if pinned_casks.any? && ((!quiet && summary_pinned.nil?) || casks.any?)
        message = "Not upgrading #{pinned_casks.count} pinned #{::Utils.pluralize("package", pinned_casks.count)}:"
        casks.any? ? ofail(message) : opoo(message)
        $stderr.puts Homebrew::Upgrade.format_upgrade_summary(pinned_versions).join("\n") if
          !quiet && summary_pinned.nil?
      end

      outdated_casks
    end

    sig { params(cask_upgrades: T::Array[String], dry_run: T.nilable(T::Boolean), verb: String).void }
    def self.show_upgrade_summary(cask_upgrades, dry_run: false, verb: "Upgrading")
      cask_upgrades = cask_upgrades.uniq
      return if cask_upgrades.empty?

      verb = "Would upgrade" if dry_run
      oh1 "#{verb} #{cask_upgrades.count} outdated #{::Utils.pluralize("package", cask_upgrades.count)}:"
      puts Homebrew::Upgrade.format_upgrade_summary(cask_upgrades).join("\n")
    end

    sig {
      params(
        casks:                      Cask,
        args:                       Homebrew::CLI::Args,
        force:                      T.nilable(T::Boolean),
        greedy:                     T.nilable(T::Boolean),
        greedy_latest:              T.nilable(T::Boolean),
        greedy_auto_updates:        T.nilable(T::Boolean),
        dry_run:                    T.nilable(T::Boolean),
        skip_cask_deps:             T.nilable(T::Boolean),
        verbose:                    T.nilable(T::Boolean),
        quiet:                      T.nilable(T::Boolean),
        binaries:                   T.nilable(T::Boolean),
        require_sha:                T.nilable(T::Boolean),
        quit:                       T::Boolean,
        skip_prefetch:              T::Boolean,
        show_upgrade_summary:       T::Boolean,
        download_queue:             T.nilable(Homebrew::DownloadQueue),
        summary_upgrades:           T.nilable(T::Array[String]),
        summary_pinned:             T.nilable(T::Array[String]),
        summary_deprecated:         T.nilable(T::Array[String]),
        summary_disabled:           T.nilable(T::Array[String]),
        prefetched_errors:          T.nilable(T::Array[StandardError]),
        upgraded_casks:             T.nilable(T::Array[Cask]),
        prefetched_cask_installers: T.nilable(T::Array[Installer]),
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
      require_sha: nil,
      quit: true,
      skip_prefetch: false,
      show_upgrade_summary: true,
      download_queue: nil,
      summary_upgrades: nil,
      summary_pinned: nil,
      summary_deprecated: nil,
      summary_disabled: nil,
      prefetched_errors: nil,
      upgraded_casks: nil,
      prefetched_cask_installers: nil
    )
      outdated_casks =
        self.outdated_casks(casks, args:, greedy:, greedy_latest:, greedy_auto_updates:, force:, quiet:,
                                   summary_pinned:, summary_disabled:)

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
        loaded_cask = if c.installed? && (installed_caskfile = c.installed_caskfile)
          begin
            CaskLoader.load_from_installed_caskfile(installed_caskfile)
          rescue CaskInvalidError, CaskUnavailableError, MethodDeprecatedError
            CaskLoader.recover_from_installed_caskfile(installed_caskfile, fallback_cask: c)
          end
        end

        if loaded_cask.nil?
          opoo <<~EOS
            The cask '#{c.token}' cannot be upgraded as-is. To fix this, run:
            brew reinstall --cask --force #{c.token}
          EOS
          next
        end

        [loaded_cask, c]
      end

      return false if upgradable_casks.empty?

      # Report each failure as it happens and carry on with the other casks,
      # rather than aborting the run; `ofail` still exits nonzero at the end.
      prefetched_errors&.each { |error| ofail error }
      failed = T.let(prefetched_errors.present?, T::Boolean)

      created_download_queue = T.let(false, T::Boolean)
      download_queue ||= if !dry_run && !skip_prefetch
        created_download_queue = true
        Homebrew::DownloadQueue.new(pour: true)
      end
      prefetched_cask_installers ||= []

      if !dry_run && !skip_prefetch
        prefetch_download_queue = download_queue || Homebrew::DownloadQueue.default
        begin
          prefetched_cask_installers.clear
          upgradable_casks.select! do |(_, cask)|
            # This is significantly easier given the weird difference in Sorbet signatures here.
            # rubocop:disable Style/DoubleNegation
            installer = Installer.new(cask, binaries: !!binaries, verbose: !!verbose, force: !!force,
                                             skip_cask_deps: !!skip_cask_deps, require_sha: !!require_sha,
                                             upgrade: true,
                                             download_queue: prefetch_download_queue, defer_fetch: true)
            # rubocop:enable Style/DoubleNegation
            begin
              installer.check_requirements
            rescue CaskError => e
              ofail e
              failed = true
              next false
            end

            prefetched_cask_installers << installer
            true
          end

          prefetched_cask_installers.replace(Homebrew::Install.enqueue_cask_installers(prefetched_cask_installers))
          prefetch_download_queue.fetch(heading: Homebrew::Install.combined_fetch_downloads_heading(
            cask_names: prefetched_cask_installers.map { |installer| installer.cask.full_name },
          ))
          Homebrew::Install.fetch_cask_dependencies(prefetched_cask_installers,
                                                    download_queue: prefetch_download_queue)
        ensure
          prefetch_download_queue.shutdown if created_download_queue
        end
      end

      return false if upgradable_casks.empty? && !failed

      cask_upgrades = upgradable_casks.map do |(old_cask, new_cask)|
        "#{new_cask.full_name} #{old_cask.version} -> #{new_cask.version}"
      end
      summary_upgrades&.concat(cask_upgrades) if dry_run
      summary_deprecated&.concat(upgradable_casks.filter_map do |(_, new_cask)|
        new_cask.full_name if new_cask.deprecated?
      end)

      show_upgrade_summary(cask_upgrades, dry_run:) if show_upgrade_summary
      return true if dry_run

      download_queue ||= Homebrew::DownloadQueue.default

      upgradable_casks.each_with_index do |(old_cask, new_cask), index|
        new_cask_installer = prefetched_cask_installers.find { |installer| installer.cask.equal?(new_cask) }
        upgrade_cask(
          old_cask, new_cask,
          binaries:, force:, skip_cask_deps:, verbose:,
          require_sha:, quit:, download_queue:, new_cask_installer:
        )
        summary_upgrades&.push(cask_upgrades.fetch(index))
        upgraded_casks&.push(new_cask)
      rescue => e
        ofail "#{new_cask.full_name}: #{e}"
        failed = true
        next
      end

      !failed
    end

    sig {
      params(
        old_cask:               Cask,
        new_cask:               Cask,
        old_signing_identities: T::Hash[String, T.nilable(Quarantine::SigningIdentity)],
        old_user_approved:      T::Hash[String, T::Boolean],
        old_unquarantined:      T::Hash[String, T::Boolean],
      ).returns(Symbol)
    }
    def self.quarantine_release_decision(old_cask, new_cask, old_signing_identities, old_user_approved,
                                         old_unquarantined)
      old_app_artifacts = old_cask.artifacts.grep(Artifact::App)
      new_app_artifacts = new_cask.artifacts.grep(Artifact::App)
      return :skip if old_app_artifacts.empty? || old_app_artifacts.length != new_app_artifacts.length
      return :unapproved unless old_app_artifacts.all? do |artifact|
        # An app with no quarantine attribute already launches without a Gatekeeper prompt, so carry
        # that state forward as well: an app whose own updater replaced the bundle should not cost the
        # user a prompt at its next upgrade. The signing identity is still checked below.
        old_user_approved.fetch(artifact.target.to_s, false) ||
        old_unquarantined.fetch(artifact.target.to_s, false)
      end

      old_app_artifacts.each_with_index do |artifact, index|
        old_identity = old_signing_identities[artifact.target.to_s]
        return :signer_unverified if old_identity.nil?

        identity_matches = Quarantine.signing_identity_match(new_app_artifacts.fetch(index).target, old_identity)
        return :signer_unverified if identity_matches.nil?
        return :signer_changed unless identity_matches
      end

      :release
    rescue
      :skip
    end

    sig { params(old_cask: Cask, new_cask: Cask).void }
    def self.reopen_apps_after_upgrade(old_cask, new_cask)
      bundle_ids = old_cask.artifacts
                           .grep(Artifact::Uninstall)
                           .flat_map(&:bundle_ids_to_reopen)
      return if bundle_ids.empty?

      # Re-register newly installed apps with Launch Services before reopening
      lsregister = Pathname(
        "/System/Library/Frameworks/CoreServices.framework" \
        "/Frameworks/LaunchServices.framework/Support/lsregister",
      )
      if lsregister.executable?
        new_cask.artifacts.grep(Artifact::App).each do |artifact|
          system(lsregister.to_s, "-f", artifact.target.to_s) if artifact.target.exist?
        end
      end

      ohai "Reopening #{bundle_ids.count} #{::Utils.pluralize("application",
                                                              bundle_ids.count)} closed during upgrade:"
      bundle_ids.each do |bundle_id|
        puts bundle_id
        # Let Launch Services supply the user's environment.
        system("open", "-b", bundle_id, unsetenv_others: true)
      end
    end
    private_class_method :reopen_apps_after_upgrade

    sig {
      params(
        old_cask:           Cask,
        new_cask:           Cask,
        binaries:           T.nilable(T::Boolean),
        force:              T.nilable(T::Boolean),
        require_sha:        T.nilable(T::Boolean),
        quit:               T::Boolean,
        skip_cask_deps:     T.nilable(T::Boolean),
        verbose:            T.nilable(T::Boolean),
        download_queue:     Homebrew::DownloadQueue,
        new_cask_installer: T.nilable(Installer),
      ).void
    }
    def self.upgrade_cask(
      old_cask, new_cask,
      binaries:, force:, require_sha:, quit:, skip_cask_deps:, verbose:, download_queue:,
      new_cask_installer: nil
    )
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
      old_tab = old_cask.tab

      new_cask.config = new_cask.default_config.merge(old_config)

      new_options = {
        binaries:,
        verbose:,
        force:,
        skip_cask_deps:,
        require_sha:,
        upgrade:        true,
        download_queue:,
      }.compact

      new_cask_installer ||= Installer.new(new_cask, **new_options, defer_fetch: true)
      raise CaskError, "Download failed for #{new_cask}." if new_cask_installer.download_failed?

      started_upgrade = false
      new_artifacts_installed = false
      old_signing_identities = T.let({}, T::Hash[String, T.nilable(Quarantine::SigningIdentity)])
      old_user_approved = T.let({}, T::Hash[String, T::Boolean])
      old_approved_paths = T.let({}, T::Hash[String, T::Array[String]])
      old_unquarantined = T.let({}, T::Hash[String, T::Boolean])

      begin
        oh1 "Upgrading #{Formatter.identifier(old_cask)}"
        puts "  #{old_cask.version} -> #{new_cask.version}"

        # Start new cask's installation steps
        new_cask_installer.prelude

        new_cask_installer.record_caveats

        new_cask_installer.fetch

        # This snapshot reads quarantine metadata, so it needs the same guard as the code below that uses it.
        if Quarantine.available?
          old_cask.artifacts.grep(Artifact::App).each do |artifact|
            user_approved = if artifact.target.exist?
              Quarantine.user_approved?(artifact.target)
            else
              false
            end
            old_user_approved[artifact.target.to_s] = user_approved
            # Only an already approved app has approvals to pass on, so skip the scan otherwise.
            if user_approved
              old_approved_paths[artifact.target.to_s] =
                Quarantine.user_approved_paths(artifact.target)
            end
            old_unquarantined[artifact.target.to_s] = if artifact.target.exist?
              Quarantine.detect(artifact.target).blank?
            else
              false
            end
            old_signing_identities[artifact.target.to_s] = Quarantine.signing_identity(artifact.target)
          end
        end

        # Move the old cask's artifacts back to staging
        old_cask_installer.start_upgrade(successor: new_cask, quit:)
        # And flag it so in case of error
        started_upgrade = true

        # Install the new cask
        new_cask_installer.stage

        new_cask_installer.install_artifacts(predecessor: old_cask)
        new_artifacts_installed = true

        if Quarantine.available?
          case quarantine_release_decision(old_cask, new_cask, old_signing_identities, old_user_approved,
                                           old_unquarantined)
          when :release
            if old_unquarantined.value?(true)
              odebug "#{new_cask.token} wasn't quarantined so approving the new version to match."
            end
            new_cask.artifacts.grep(Artifact::App).each do |artifact|
              Quarantine.inherit_user_approval!(
                download_path:  artifact.target,
                approved_paths: old_approved_paths.fetch(artifact.target.to_s, []),
              )
            rescue CaskQuarantineReleaseError => e
              odebug e
              opoo "Homebrew couldn't inherit #{new_cask.token}'s quarantine approval so macOS may prompt at " \
                   "next launch."
            end
          when :signer_changed
            opoo "#{new_cask.token}'s signer changed so macOS may prompt at next launch."
          when :signer_unverified
            opoo "Homebrew couldn't verify #{new_cask.token}'s signer so macOS may prompt at next launch."
          when :unapproved
            message = "#{new_cask.token} wasn't quarantine approved so not approving now. " \
                      "macOS may prompt at next launch."
            if verbose
              ohai message
            else
              odebug message
            end
          end
        end

        # If successful, wipe the old cask from staging.
        old_cask_installer.finalize_upgrade

        reopen_apps_after_upgrade(old_cask, new_cask) if quit
      rescue => e
        begin
          new_cask_installer.uninstall_artifacts(successor: old_cask, quit:) if new_artifacts_installed
          new_cask_installer.purge_versioned_files
          old_cask_installer.revert_upgrade(predecessor: new_cask) if started_upgrade
        rescue => rollback_error
          opoo "Rolling back the failed upgrade of #{old_cask.token} also failed: " \
               "#{rollback_error.class}: #{rollback_error.message}"
          if (rollback_backtrace = rollback_error.backtrace)
            odebug "Rollback backtrace:", rollback_backtrace
          end
        end
        new_cask_installer.purge_staged_download
        raise e
      end

      # Wait until rollback is no longer possible so failures keep the old
      # receipt, while successful upgrades can load artifacts next time.
      tab = Tab.create(new_cask)
      tab.installed_on_request = old_tab.tabfile.nil? || old_tab.installed_on_request
      tab.write

      end_time = Time.now
      Homebrew.messages.package_installed(new_cask.token, end_time - start_time)
    end
  end
end
