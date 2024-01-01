# typed: true
# frozen_string_literal: true

require "attrable"
require "formula_installer"
require "unpack_strategy"
require "utils/topological_hash"

require "cask/config"
require "cask/download"
require "cask/migrator"
require "cask/quarantine"

require "cgi"

module Cask
  # Installer for a {Cask}.
  #
  # @api private
  class Installer
    extend Attrable

    def initialize(cask, command: SystemCommand, force: false, adopt: false,
                   skip_cask_deps: false, binaries: true, verbose: false,
                   zap: false, require_sha: false, upgrade: false, reinstall: false,
                   installed_as_dependency: false, quarantine: true,
                   verify_download_integrity: true, quiet: false)
      @cask = cask
      @command = command
      @force = force
      @adopt = adopt
      @skip_cask_deps = skip_cask_deps
      @binaries = binaries
      @verbose = verbose
      @zap = zap
      @require_sha = require_sha
      @reinstall = reinstall
      @upgrade = upgrade
      @installed_as_dependency = installed_as_dependency
      @quarantine = quarantine
      @verify_download_integrity = verify_download_integrity
      @quiet = quiet
    end

    attr_predicate :binaries?, :force?, :adopt?, :skip_cask_deps?, :require_sha?,
                   :reinstall?, :upgrade?, :verbose?, :zap?, :installed_as_dependency?,
                   :quarantine?, :quiet?

    def self.caveats(cask)
      odebug "Printing caveats"

      caveats = cask.caveats
      return if caveats.empty?

      Homebrew.messages.record_caveats(cask.token, caveats)

      <<~EOS
        #{ohai_title "Caveats"}
        #{caveats}
      EOS
    end

    sig { params(quiet: T.nilable(T::Boolean), timeout: T.nilable(T.any(Integer, Float))).void }
    def fetch(quiet: nil, timeout: nil)
      odebug "Cask::Installer#fetch"

      load_cask_from_source_api! if @cask.loaded_from_api? && @cask.caskfile_only?
      verify_has_sha if require_sha? && !force?
      check_requirements

      download(quiet: quiet, timeout: timeout)

      satisfy_cask_and_formula_dependencies
    end

    def stage
      odebug "Cask::Installer#stage"

      Caskroom.ensure_caskroom_exists

      extract_primary_container
      save_caskfile
    rescue => e
      purge_versioned_files
      raise e
    end

    def install
      start_time = Time.now
      odebug "Cask::Installer#install"

      Migrator.migrate_if_needed(@cask)

      old_config = @cask.config
      predecessor = @cask if reinstall? && @cask.installed?

      check_deprecate_disable
      check_conflicts

      print caveats
      fetch
      uninstall_existing_cask if reinstall?

      backup if force? && @cask.staged_path.exist? && @cask.metadata_versioned_path.exist?

      oh1 "Installing Cask #{Formatter.identifier(@cask)}"
      opoo "macOS's Gatekeeper has been disabled for this Cask" unless quarantine?
      stage

      @cask.config = @cask.default_config.merge(old_config)

      install_artifacts(predecessor: predecessor)

      if (tap = @cask.tap) && tap.should_report_analytics?
        ::Utils::Analytics.report_event(:cask_install, package_name: @cask.token, tap_name: tap.name,
on_request: true)
      end

      purge_backed_up_versioned_files

      puts summary
      end_time = Time.now
      Homebrew.messages.package_installed(@cask.token, end_time - start_time)
    rescue
      restore_backup
      raise
    end

    def check_deprecate_disable
      deprecate_disable_type = DeprecateDisable.type(@cask)
      return if deprecate_disable_type.nil?

      case deprecate_disable_type
      when :deprecated
        opoo "#{@cask.token} has been #{DeprecateDisable.message(@cask)}"
      when :disabled
        raise CaskCannotBeInstalledError.new(@cask, DeprecateDisable.message(@cask))
      end
    end

    def check_conflicts
      return unless @cask.conflicts_with

      @cask.conflicts_with[:cask].each do |conflicting_cask|
        if (match = conflicting_cask.match(HOMEBREW_TAP_CASK_REGEX))
          conflicting_cask_tap = Tap.fetch(match[1], match[2])
          next unless conflicting_cask_tap.installed?
        end

        conflicting_cask = CaskLoader.load(conflicting_cask)
        raise CaskConflictError.new(@cask, conflicting_cask) if conflicting_cask.installed?
      rescue CaskUnavailableError
        next # Ignore conflicting Casks that do not exist.
      end
    end

    def uninstall_existing_cask
      return unless @cask.installed?

      # Always force uninstallation, ignore method parameter
      cask_installer = Installer.new(@cask, verbose: verbose?, force: true, upgrade: upgrade?, reinstall: true)
      zap? ? cask_installer.zap : cask_installer.uninstall(successor: @cask)
    end

    sig { returns(String) }
    def summary
      s = +""
      s << "#{Homebrew::EnvConfig.install_badge}  " unless Homebrew::EnvConfig.no_emoji?
      s << "#{@cask} was successfully #{upgrade? ? "upgraded" : "installed"}!"
      s.freeze
    end

    sig { returns(Download) }
    def downloader
      @downloader ||= Download.new(@cask, quarantine: quarantine?)
    end

    sig { params(quiet: T.nilable(T::Boolean), timeout: T.nilable(T.any(Integer, Float))).returns(Pathname) }
    def download(quiet: nil, timeout: nil)
      # Store cask download path in cask to prevent multiple downloads in a row when checking if it's outdated
      @cask.download ||= downloader.fetch(quiet: quiet, verify_download_integrity: @verify_download_integrity,
                                          timeout: timeout)
    end

    def verify_has_sha
      odebug "Checking cask has checksum"
      return if @cask.sha256 != :no_check

      raise CaskError, <<~EOS
        Cask '#{@cask}' does not have a sha256 checksum defined and was not installed.
        This means you have the #{Formatter.identifier("--require-sha")} option set, perhaps in your HOMEBREW_CASK_OPTS.
      EOS
    end

    def primary_container
      @primary_container ||= begin
        downloaded_path = download(quiet: true)
        UnpackStrategy.detect(downloaded_path, type: @cask.container&.type, merge_xattrs: true)
      end
    end

    def extract_primary_container(to: @cask.staged_path)
      odebug "Extracting primary container"

      odebug "Using container class #{primary_container.class} for #{primary_container.path}"

      basename = downloader.basename

      if (nested_container = @cask.container&.nested)
        Dir.mktmpdir do |tmpdir|
          tmpdir = Pathname(tmpdir)
          primary_container.extract(to: tmpdir, basename: basename, verbose: verbose?)

          FileUtils.chmod_R "+rw", tmpdir/nested_container, force: true, verbose: verbose?

          UnpackStrategy.detect(tmpdir/nested_container, merge_xattrs: true)
                        .extract_nestedly(to: to, verbose: verbose?)
        end
      else
        primary_container.extract_nestedly(to: to, basename: basename, verbose: verbose?)
      end

      return unless quarantine?
      return unless Quarantine.available?

      Quarantine.propagate(from: primary_container.path, to: to)
    end

    sig { params(predecessor: T.nilable(Cask)).void }
    def install_artifacts(predecessor: nil)
      artifacts = @cask.artifacts
      already_installed_artifacts = []

      odebug "Installing artifacts"

      artifacts.each do |artifact|
        next unless artifact.respond_to?(:install_phase)

        odebug "Installing artifact of class #{artifact.class}"

        next if artifact.is_a?(Artifact::Binary) && !binaries?

        artifact.install_phase(
          command: @command, verbose: verbose?, adopt: adopt?, force: force?, predecessor: predecessor,
        )
        already_installed_artifacts.unshift(artifact)
      end

      save_config_file
      save_download_sha if @cask.version.latest?
    rescue => e
      begin
        already_installed_artifacts&.each do |artifact|
          if artifact.respond_to?(:uninstall_phase)
            odebug "Reverting installation of artifact of class #{artifact.class}"
            artifact.uninstall_phase(command: @command, verbose: verbose?, force: force?)
          end

          next unless artifact.respond_to?(:post_uninstall_phase)

          odebug "Reverting installation of artifact of class #{artifact.class}"
          artifact.post_uninstall_phase(command: @command, verbose: verbose?, force: force?)
        end
      ensure
        purge_versioned_files
        raise e
      end
    end

    def check_requirements
      check_macos_requirements
      check_arch_requirements
    end

    def check_macos_requirements
      return unless @cask.depends_on.macos
      return if @cask.depends_on.macos.satisfied?

      raise CaskError, @cask.depends_on.macos.message(type: :cask)
    end

    def check_arch_requirements
      return if @cask.depends_on.arch.nil?

      @current_arch ||= { type: Hardware::CPU.type, bits: Hardware::CPU.bits }
      return if @cask.depends_on.arch.any? do |arch|
        arch[:type] == @current_arch[:type] &&
        Array(arch[:bits]).include?(@current_arch[:bits])
      end

      raise CaskError,
            "Cask #{@cask} depends on hardware architecture being one of " \
            "[#{@cask.depends_on.arch.map(&:to_s).join(", ")}], " \
            "but you are running #{@current_arch}."
    end

    def cask_and_formula_dependencies
      return @cask_and_formula_dependencies if @cask_and_formula_dependencies

      graph = ::Utils::TopologicalHash.graph_package_dependencies(@cask)

      raise CaskSelfReferencingDependencyError, @cask.token if graph[@cask].include?(@cask)

      ::Utils::TopologicalHash.graph_package_dependencies(primary_container.dependencies, graph)

      begin
        @cask_and_formula_dependencies = graph.tsort - [@cask]
      rescue TSort::Cyclic
        strongly_connected_components = graph.strongly_connected_components.sort_by(&:count)
        cyclic_dependencies = strongly_connected_components.last - [@cask]
        raise CaskCyclicDependencyError.new(@cask.token, cyclic_dependencies.to_sentence)
      end
    end

    def missing_cask_and_formula_dependencies
      cask_and_formula_dependencies.reject do |cask_or_formula|
        case cask_or_formula
        when Formula
          cask_or_formula.any_version_installed? && cask_or_formula.optlinked?
        when Cask
          cask_or_formula.installed?
        end
      end
    end

    def satisfy_cask_and_formula_dependencies
      return if installed_as_dependency?

      formulae_and_casks = cask_and_formula_dependencies

      return if formulae_and_casks.empty?

      missing_formulae_and_casks = missing_cask_and_formula_dependencies

      if missing_formulae_and_casks.empty?
        puts "All formula dependencies satisfied."
        return
      end

      ohai "Installing dependencies: #{missing_formulae_and_casks.map(&:to_s).join(", ")}"
      missing_formulae_and_casks.each do |cask_or_formula|
        if cask_or_formula.is_a?(Cask)
          if skip_cask_deps?
            opoo "`--skip-cask-deps` is set; skipping installation of #{cask_or_formula}."
            next
          end

          Installer.new(
            cask_or_formula,
            adopt:                   adopt?,
            binaries:                binaries?,
            verbose:                 verbose?,
            installed_as_dependency: true,
            force:                   false,
          ).install
        else
          fi = FormulaInstaller.new(
            cask_or_formula,
            **{
              show_header:             true,
              installed_as_dependency: true,
              installed_on_request:    false,
              verbose:                 verbose?,
            }.compact,
          )
          fi.prelude
          fi.fetch
          fi.install
          fi.finish
        end
      end
    end

    def caveats
      self.class.caveats(@cask)
    end

    def metadata_subdir
      @metadata_subdir ||= @cask.metadata_subdir("Casks", timestamp: :now, create: true)
    end

    def save_caskfile
      old_savedir = @cask.metadata_timestamped_path

      return if @cask.source.blank?

      extension = @cask.loaded_from_api? ? "json" : "rb"
      (metadata_subdir/"#{@cask.token}.#{extension}").write @cask.source
      old_savedir&.rmtree
    end

    def save_config_file
      @cask.config_path.atomic_write(@cask.config.to_json)
    end

    def save_download_sha
      @cask.download_sha_path.atomic_write(@cask.new_download_sha) if @cask.checksumable?
    end

    sig { params(successor: T.nilable(Cask)).void }
    def uninstall(successor: nil)
      load_installed_caskfile!
      oh1 "Uninstalling Cask #{Formatter.identifier(@cask)}"
      uninstall_artifacts(clear: true, successor: successor)
      if !reinstall? && !upgrade?
        remove_download_sha
        remove_config_file
      end
      purge_versioned_files
      purge_caskroom_path if force?
    end

    def remove_config_file
      FileUtils.rm_f @cask.config_path
      @cask.config_path.parent.rmdir_if_possible
    end

    def remove_download_sha
      FileUtils.rm_f @cask.download_sha_path
      @cask.download_sha_path.parent.rmdir_if_possible
    end

    sig { params(successor: T.nilable(Cask)).void }
    def start_upgrade(successor:)
      uninstall_artifacts(successor: successor)
      backup
    end

    def backup
      @cask.staged_path.rename backup_path
      @cask.metadata_versioned_path.rename backup_metadata_path
    end

    def restore_backup
      return if !backup_path.directory? || !backup_metadata_path.directory?

      @cask.staged_path.rmtree if @cask.staged_path.exist?
      @cask.metadata_versioned_path.rmtree if @cask.metadata_versioned_path.exist?

      backup_path.rename @cask.staged_path
      backup_metadata_path.rename @cask.metadata_versioned_path
    end

    sig { params(predecessor: Cask).void }
    def revert_upgrade(predecessor:)
      opoo "Reverting upgrade for Cask #{@cask}"
      restore_backup
      install_artifacts(predecessor: predecessor)
    end

    def finalize_upgrade
      ohai "Purging files for version #{@cask.version} of Cask #{@cask}"

      purge_backed_up_versioned_files

      puts summary
    end

    sig { params(clear: T::Boolean, successor: T.nilable(Cask)).void }
    def uninstall_artifacts(clear: false, successor: nil)
      artifacts = @cask.artifacts

      odebug "Uninstalling artifacts"
      odebug "#{::Utils.pluralize("artifact", artifacts.length, include_count: true)} defined", artifacts

      artifacts.each do |artifact|
        if artifact.respond_to?(:uninstall_phase)
          odebug "Uninstalling artifact of class #{artifact.class}"
          artifact.uninstall_phase(
            command:   @command,
            verbose:   verbose?,
            skip:      clear,
            force:     force?,
            successor: successor,
          )
        end

        next unless artifact.respond_to?(:post_uninstall_phase)

        odebug "Post-uninstalling artifact of class #{artifact.class}"
        artifact.post_uninstall_phase(
          command:   @command,
          verbose:   verbose?,
          skip:      clear,
          force:     force?,
          successor: successor,
        )
      end
    end

    def zap
      load_installed_caskfile!
      ohai "Implied `brew uninstall --cask #{@cask}`"
      uninstall_artifacts
      if (zap_stanzas = @cask.artifacts.select { |a| a.is_a?(Artifact::Zap) }).empty?
        opoo "No zap stanza present for Cask '#{@cask}'"
      else
        ohai "Dispatching zap stanza"
        zap_stanzas.each do |stanza|
          stanza.zap_phase(command: @command, verbose: verbose?, force: force?)
        end
      end
      ohai "Removing all staged versions of Cask '#{@cask}'"
      purge_caskroom_path
    end

    def backup_path
      return if @cask.staged_path.nil?

      Pathname("#{@cask.staged_path}.upgrading")
    end

    def backup_metadata_path
      return if @cask.metadata_versioned_path.nil?

      Pathname("#{@cask.metadata_versioned_path}.upgrading")
    end

    def gain_permissions_remove(path)
      Utils.gain_permissions_remove(path, command: @command)
    end

    def purge_backed_up_versioned_files
      # versioned staged distribution
      gain_permissions_remove(backup_path) if backup_path&.exist?

      # Homebrew Cask metadata
      return unless backup_metadata_path.directory?

      backup_metadata_path.children.each do |subdir|
        gain_permissions_remove(subdir)
      end
      backup_metadata_path.rmdir_if_possible
    end

    def purge_versioned_files
      ohai "Purging files for version #{@cask.version} of Cask #{@cask}"

      # versioned staged distribution
      gain_permissions_remove(@cask.staged_path) if @cask.staged_path&.exist?

      # Homebrew Cask metadata
      if @cask.metadata_versioned_path.directory?
        @cask.metadata_versioned_path.children.each do |subdir|
          gain_permissions_remove(subdir)
        end

        @cask.metadata_versioned_path.rmdir_if_possible
      end
      @cask.metadata_main_container_path.rmdir_if_possible unless upgrade?

      # toplevel staged distribution
      @cask.caskroom_path.rmdir_if_possible unless upgrade?

      # Remove symlinks for renamed casks if they are now broken.
      @cask.old_tokens.each do |old_token|
        old_caskroom_path = Caskroom.path/old_token
        FileUtils.rm old_caskroom_path if old_caskroom_path.symlink? && !old_caskroom_path.exist?
      end
    end

    def purge_caskroom_path
      odebug "Purging all staged versions of Cask #{@cask}"
      gain_permissions_remove(@cask.caskroom_path)
    end

    private

    # load the same cask file that was used for installation, if possible
    def load_installed_caskfile!
      Migrator.migrate_if_needed(@cask)

      installed_caskfile = @cask.installed_caskfile

      if installed_caskfile&.exist?
        begin
          @cask = CaskLoader.load(installed_caskfile)
          return
        rescue CaskInvalidError
          # could be caused by trying to load outdated caskfile
        end
      end

      load_cask_from_source_api! if @cask.loaded_from_api? && @cask.caskfile_only?
      # otherwise we default to the current cask
    end

    def load_cask_from_source_api!
      @cask = Homebrew::API::Cask.source_download(@cask)
    end
  end
end
