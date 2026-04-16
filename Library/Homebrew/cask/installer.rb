# typed: strict
# frozen_string_literal: true

require "formula_installer"
require "unpack_strategy"
require "utils/topological_hash"
require "utils/analytics"
require "utils/output"

require "cask/config"
require "cask/download"
require "cask/migrator"
require "cask/quarantine"
require "cask/tab"

module Cask
  # Installer for a {Cask}.
  class Installer
    extend ::Utils::Output::Mixin
    include ::Utils::Output::Mixin

    sig {
      params(
        cask: ::Cask::Cask, command: T.class_of(SystemCommand), force: T::Boolean, adopt: T::Boolean,
        skip_cask_deps: T::Boolean, binaries: T::Boolean, verbose: T::Boolean, zap: T::Boolean,
        require_sha: T::Boolean, upgrade: T::Boolean, reinstall: T::Boolean, installed_as_dependency: T::Boolean,
        installed_on_request: T::Boolean, quarantine: T::Boolean, verify_download_integrity: T::Boolean,
        quiet: T::Boolean, download_queue: Homebrew::DownloadQueue, defer_fetch: T::Boolean
      ).void
    }
    def initialize(cask, command: SystemCommand, force: false, adopt: false,
                   skip_cask_deps: false, binaries: true, verbose: false,
                   zap: false, require_sha: false, upgrade: false, reinstall: false,
                   installed_as_dependency: false, installed_on_request: true,
                   quarantine: true, verify_download_integrity: true, quiet: false,
                   download_queue: Homebrew.default_download_queue, defer_fetch: false)
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
      @installed_on_request = installed_on_request
      @quarantine = quarantine
      @verify_download_integrity = verify_download_integrity
      @quiet = quiet
      @download_queue = download_queue
      @defer_fetch = defer_fetch
      @ran_prelude = T.let(false, T::Boolean)
      @cask_and_formula_dependencies = T.let(nil, T.nilable(T::Array[T.any(Formula, ::Cask::Cask)]))
    end

    sig { returns(T::Boolean) }
    def adopt? = @adopt

    sig { returns(T::Boolean) }
    def binaries? = @binaries

    sig { returns(T::Boolean) }
    def force? = @force

    sig { returns(T::Boolean) }
    def installed_as_dependency? = @installed_as_dependency

    sig { returns(T::Boolean) }
    def installed_on_request? = @installed_on_request

    sig { returns(T::Boolean) }
    def quarantine? = @quarantine

    sig { returns(T::Boolean) }
    def quiet? = @quiet

    sig { returns(T::Boolean) }
    def reinstall? = @reinstall

    sig { returns(T::Boolean) }
    def require_sha? = @require_sha

    sig { returns(T::Boolean) }
    def skip_cask_deps? = @skip_cask_deps

    sig { returns(T::Boolean) }
    def upgrade? = @upgrade

    sig { returns(T::Boolean) }
    def verbose? = @verbose

    sig { returns(T::Boolean) }
    def zap? = @zap

    sig { params(cask: ::Cask::Cask).returns(T.nilable(String)) }
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

      load_cask_from_source_api! if cask_from_source_api?
      check_requirements

      forbidden_tap_check
      forbidden_cask_and_formula_check
      forbidden_cask_artifacts_check

      download(quiet:, timeout:) unless @defer_fetch

      satisfy_cask_and_formula_dependencies
    end

    sig { void }
    def stage
      odebug "Cask::Installer#stage"

      Caskroom.ensure_caskroom_exists

      extract_primary_container
      process_rename_operations
      save_caskfile
    rescue => e
      purge_versioned_files
      raise e
    end

    sig { void }
    def install
      start_time = Time.now
      odebug "Cask::Installer#install"

      Migrator.migrate_if_needed(@cask)

      old_config = @cask.config
      predecessor = @cask if reinstall? && @cask.installed?

      prelude

      print caveats
      fetch
      uninstall_existing_cask if reinstall?

      backup if force? && @cask.staged_path.exist? && @cask.metadata_versioned_path.exist?

      oh1 "Installing Cask #{Formatter.identifier(@cask)}"
      # GitHub Actions globally disables Gatekeeper.
      unless quarantine?
        opoo_outside_github_actions "--no-quarantine bypasses macOS’s Gatekeeper, reducing system security. " \
                                    "Do not use this flag unless you understand the risks."
      end
      stage

      @cask.config = @cask.default_config.merge(old_config)

      install_artifacts(predecessor:)

      tab = Tab.create(@cask)
      tab.installed_as_dependency = installed_as_dependency?
      tab.installed_on_request = installed_on_request?
      tab.write

      if (tap = @cask.tap) && tap.should_report_analytics?
        ::Utils::Analytics.report_package_event(:cask_install, package_name: @cask.token, tap_name: tap.name,
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

    sig { void }
    def check_deprecate_disable
      deprecate_disable_type = DeprecateDisable.type(@cask)
      return if deprecate_disable_type.nil?

      message = DeprecateDisable.message(@cask).to_s
      message_full = "#{@cask.token} has been #{message}"

      case deprecate_disable_type
      when :deprecated
        opoo message_full
      when :disabled
        GitHub::Actions.puts_annotation_if_env_set!(:error, message)
        raise CaskCannotBeInstalledError.new(@cask, message)
      end
    end

    sig { void }
    def check_conflicts
      return unless @cask.conflicts_with

      @cask.conflicts_with[:cask].each do |conflicting_cask|
        if (conflicting_cask_tap_with_token = Tap.with_cask_token(conflicting_cask))
          conflicting_cask_tap, = conflicting_cask_tap_with_token
          next unless conflicting_cask_tap.installed?
        end

        conflicting_cask = CaskLoader.load(conflicting_cask)
        raise CaskConflictError.new(@cask, conflicting_cask) if conflicting_cask.installed?
      rescue CaskUnavailableError
        next # Ignore conflicting Casks that do not exist.
      end
    end

    sig { void }
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
      @downloader ||= T.let(
        Download.new(@cask, quarantine: quarantine?, require_sha: require_sha? && !force?),
        T.nilable(Download),
      )
    end

    sig { params(quiet: T.nilable(T::Boolean), timeout: T.nilable(T.any(Integer, Float))).returns(Pathname) }
    def download(quiet: nil, timeout: nil)
      # Store cask download path in cask to prevent multiple downloads in a row when checking if it's outdated
      @cask.download ||= downloader.fetch(quiet:, verify_download_integrity: @verify_download_integrity,
                                          timeout:)
    end

    sig { returns(UnpackStrategy) }
    def primary_container
      @primary_container ||= T.let(
        begin
          downloaded_path = download(quiet: true)
          UnpackStrategy.detect(downloaded_path, type: @cask.container&.type, merge_xattrs: true)
        end,
        T.nilable(UnpackStrategy),
      )
    end

    sig { returns(ArtifactSet) }
    def artifacts
      @cask.artifacts
    end

    sig { params(to: Pathname).void }
    def extract_primary_container(to: @cask.staged_path)
      odebug "Extracting primary container"

      container = primary_container
      raise "unexpected nil primary_container" unless container

      odebug "Using container class #{container.class} for #{container.path}"

      basename = downloader.basename

      if (nested_container = @cask.container&.nested)
        Dir.mktmpdir("cask-installer", HOMEBREW_TEMP) do |tmpdir|
          tmpdir = Pathname(tmpdir)
          container.extract(to: tmpdir, basename:, verbose: verbose?)

          FileUtils.chmod_R "+rw", tmpdir/nested_container, force: true, verbose: verbose?

          UnpackStrategy.detect(tmpdir/nested_container, merge_xattrs: true)
                        .extract_nestedly(to:, verbose: verbose?)
        end
      else
        container.extract_nestedly(to:, basename:, verbose: verbose?)
      end

      return unless quarantine?
      return unless Quarantine.available?

      Quarantine.propagate(from: container.path, to:)
    end

    sig { params(target_dir: T.nilable(Pathname)).void }
    def process_rename_operations(target_dir: nil)
      return if @cask.rename.empty?

      working_dir = target_dir || @cask.staged_path
      odebug "Processing rename operations in #{working_dir}"

      @cask.rename.each do |rename_operation|
        odebug "Renaming #{rename_operation.from} to #{rename_operation.to}"
        rename_operation.perform_rename(working_dir)
      end
    end

    sig { params(predecessor: T.nilable(Cask)).void }
    def install_artifacts(predecessor: nil)
      already_installed_artifacts = []

      odebug "Installing artifacts"

      artifacts.each do |artifact|
        next unless artifact.respond_to?(:install_phase)

        odebug "Installing artifact of class #{artifact.class}"

        next if artifact.is_a?(Artifact::Binary) && !binaries?

        artifact = T.cast(
          artifact,
          T.any(
            Artifact::AbstractFlightBlock,
            Artifact::GeneratedCompletion,
            Artifact::Installer,
            Artifact::KeyboardLayout,
            Artifact::Mdimporter,
            Artifact::Moved,
            Artifact::Pkg,
            Artifact::Qlplugin,
            Artifact::Symlinked,
          ),
        )

        artifact.install_phase(
          command: @command, verbose: verbose?, adopt: adopt?, auto_updates: @cask.auto_updates,
          force: force?, predecessor:
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

    sig { void }
    def check_requirements
      check_stanza_os_requirements
      check_macos_requirements
      check_arch_requirements
    end

    sig { void }
    def check_stanza_os_requirements
      nil
    end

    sig { void }
    def check_macos_requirements
      return unless @cask.depends_on.macos
      return if @cask.depends_on.macos.satisfied?

      raise CaskError, @cask.depends_on.macos.message(type: :cask)
    end

    sig { void }
    def check_arch_requirements
      return if @cask.depends_on.arch.nil?

      @current_arch = T.let(@current_arch, T.nilable(T::Hash[Symbol, T.untyped]))
      @current_arch ||= { type: Hardware::CPU.type, bits: Hardware::CPU.bits }
      return if @cask.depends_on.arch.any? do |arch|
        arch[:type] == @current_arch[:type] &&
        Array(arch[:bits]).include?(@current_arch[:bits])
      end

      raise CaskError,
            "Cask #{@cask} depends on hardware architecture being one of " \
            "[#{@cask.depends_on.arch.join(", ")}], " \
            "but you are running #{@current_arch}."
    end

    sig { returns(T::Array[T.any(Formula, ::Cask::Cask)]) }
    def cask_and_formula_dependencies
      return @cask_and_formula_dependencies if @cask_and_formula_dependencies

      graph = ::Utils::TopologicalHash.graph_package_dependencies(@cask)

      raise CaskSelfReferencingDependencyError, @cask.token if graph.fetch(@cask).include?(@cask)

      pc = primary_container
      raise "unexpected nil primary_container" unless pc

      ::Utils::TopologicalHash.graph_package_dependencies(pc.dependencies, graph)

      begin
        @cask_and_formula_dependencies = graph.tsort - [@cask]
      rescue TSort::Cyclic
        strongly_connected_components = graph.strongly_connected_components.sort_by(&:count)
        cyclic_dependencies = strongly_connected_components.last - [@cask]
        raise CaskCyclicDependencyError.new(@cask.token, cyclic_dependencies.to_sentence)
      end
    end

    sig { returns(T::Array[T.any(Formula, ::Cask::Cask)]) }
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

    sig { void }
    def satisfy_cask_and_formula_dependencies
      return if installed_as_dependency?

      formulae_and_casks = cask_and_formula_dependencies

      return if formulae_and_casks.empty?

      missing_formulae_and_casks = missing_cask_and_formula_dependencies

      if missing_formulae_and_casks.empty?
        puts "All dependencies satisfied."
        return
      end

      ohai "Installing dependencies: #{missing_formulae_and_casks.join(", ")}"
      cask_installers = T.let([], T::Array[Installer])
      formula_installers = T.let([], T::Array[FormulaInstaller])

      missing_formulae_and_casks.each do |cask_or_formula|
        if cask_or_formula.is_a?(Cask)
          if skip_cask_deps?
            opoo "`--skip-cask-deps` is set; skipping installation of #{cask_or_formula}."
            next
          end

          cask_installers << Installer.new(
            cask_or_formula,
            adopt:                   adopt?,
            binaries:                binaries?,
            force:                   false,
            installed_as_dependency: true,
            installed_on_request:    false,
            quarantine:              quarantine?,
            quiet:                   quiet?,
            require_sha:             require_sha?,
            verbose:                 verbose?,
          )
        else
          formula_installers << FormulaInstaller.new(
            cask_or_formula,
            **{
              show_header:             true,
              installed_as_dependency: true,
              installed_on_request:    false,
              verbose:                 verbose?,
            }.compact,
          )
        end
      end

      cask_installers.each(&:install)
      return if formula_installers.blank?

      Homebrew::Install.perform_preinstall_checks_once
      valid_formula_installers = Homebrew::Install.fetch_formulae(formula_installers)
      valid_formula_installers.each do |formula_installer|
        formula_installer.install
        formula_installer.finish
      end
    end

    sig { returns(T.nilable(String)) }
    def caveats
      self.class.caveats(@cask)
    end

    sig { returns(Pathname) }
    def metadata_subdir
      @metadata_subdir ||= T.let(
        begin
          msd = @cask.metadata_subdir("Casks", timestamp: :now, create: true)
          raise "unexpected nil metadata_subdir" unless msd

          msd
        end,
        T.nilable(Pathname),
      )
    end

    sig { void }
    def save_caskfile
      old_savedir = @cask.metadata_timestamped_path

      return if @cask.source.blank?

      extension = if @cask.loaded_from_internal_api?
        "internal.json"
      elsif @cask.loaded_from_api?
        "json"
      else
        "rb"
      end

      source = if @cask.loaded_from_internal_api? && (api_source = @cask.api_source)
        api_source = api_source.merge({ "tap_git_head" => @cask.tap_git_head })
        JSON.pretty_generate(api_source)
      else
        @cask.source
      end

      (metadata_subdir/"#{@cask.token}.#{extension}").write source
      FileUtils.rm_r(old_savedir) if old_savedir
    end

    sig { void }
    def save_config_file
      @cask.config_path.atomic_write(@cask.config.to_json)
    end

    sig { void }
    def save_download_sha
      return unless @cask.checksumable?

      @cask.download_sha_path.atomic_write(@cask.new_download_sha)
    end

    sig { params(successor: T.nilable(Cask)).void }
    def uninstall(successor: nil)
      load_installed_caskfile!
      oh1 "Uninstalling Cask #{Formatter.identifier(@cask)}"
      uninstall_artifacts(clear: true, successor:)
      if !reinstall? && !upgrade?
        remove_tabfile
        remove_download_sha
        remove_config_file
      end
      purge_versioned_files
      purge_caskroom_path if force?
    end

    sig { void }
    def remove_tabfile
      tabfile = @cask.tab.tabfile
      FileUtils.rm_f tabfile if tabfile
      @cask.config_path.parent.rmdir_if_possible
    end

    sig { void }
    def remove_config_file
      FileUtils.rm_f @cask.config_path
      @cask.config_path.parent.rmdir_if_possible
    end

    sig { void }
    def remove_download_sha
      FileUtils.rm_f @cask.download_sha_path
      @cask.download_sha_path.parent.rmdir_if_possible
    end

    sig { params(successor: T.nilable(Cask)).void }
    def start_upgrade(successor:)
      uninstall_artifacts(successor:)
      backup
    end

    sig { void }
    def backup
      bp = backup_path
      raise "unexpected nil backup_path" unless bp

      bmp = backup_metadata_path
      raise "unexpected nil backup_metadata_path" unless bmp

      @cask.staged_path.rename bp.to_s
      @cask.metadata_versioned_path.rename bmp.to_s
    end

    sig { void }
    def restore_backup
      bp = backup_path
      return unless bp

      bmp = backup_metadata_path
      return unless bmp

      return if !bp.directory? || !bmp.directory?

      FileUtils.rm_r(@cask.staged_path) if @cask.staged_path.exist?
      FileUtils.rm_r(@cask.metadata_versioned_path) if @cask.metadata_versioned_path.exist?

      bp.rename @cask.staged_path.to_s
      bmp.rename @cask.metadata_versioned_path.to_s
    end

    sig { params(predecessor: Cask).void }
    def revert_upgrade(predecessor:)
      opoo "Reverting upgrade for Cask #{@cask}"
      restore_backup
      install_artifacts(predecessor:)
    end

    sig { void }
    def finalize_upgrade
      ohai "Purging files for version #{@cask.version} of Cask #{@cask}"

      purge_backed_up_versioned_files

      puts summary
    end

    sig { params(clear: T::Boolean, successor: T.nilable(Cask)).void }
    def uninstall_artifacts(clear: false, successor: nil)
      odebug "Uninstalling artifacts"
      odebug "#{::Utils.pluralize("artifact", artifacts.length, include_count: true)} defined", artifacts

      artifacts.each do |artifact|
        if artifact.respond_to?(:uninstall_phase)
          artifact = T.cast(
            artifact,
            T.any(
              Artifact::AbstractFlightBlock,
              Artifact::GeneratedCompletion,
              Artifact::KeyboardLayout,
              Artifact::Moved,
              Artifact::Qlplugin,
              Artifact::Symlinked,
              Artifact::Uninstall,
            ),
          )

          odebug "Uninstalling artifact of class #{artifact.class}"
          artifact.uninstall_phase(
            command:   @command,
            verbose:   verbose?,
            skip:      clear,
            force:     force?,
            successor:,
            upgrade:   upgrade?,
            reinstall: reinstall?,
          )
        end

        next unless artifact.respond_to?(:post_uninstall_phase)

        artifact = T.cast(artifact, Artifact::Uninstall)

        odebug "Post-uninstalling artifact of class #{artifact.class}"
        artifact.post_uninstall_phase(
          command:   @command,
          verbose:   verbose?,
          skip:      clear,
          force:     force?,
          successor:,
        )
      end
    end

    sig { void }
    def zap
      load_installed_caskfile!
      uninstall_artifacts
      if (zap_stanzas = @cask.artifacts.grep(Artifact::Zap)).empty?
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

    sig { returns(T.nilable(Pathname)) }
    def backup_path
      return if @cask.staged_path.nil?

      Pathname("#{@cask.staged_path}.upgrading")
    end

    sig { returns(T.nilable(Pathname)) }
    def backup_metadata_path
      return if @cask.metadata_versioned_path.nil?

      Pathname("#{@cask.metadata_versioned_path}.upgrading")
    end

    sig { params(path: Pathname).void }
    def gain_permissions_remove(path)
      Utils.gain_permissions_remove(path, command: @command)
    end

    sig { void }
    def purge_backed_up_versioned_files
      # versioned staged distribution
      gain_permissions_remove(T.must(backup_path)) if backup_path&.exist?

      # Homebrew Cask metadata
      bmp = backup_metadata_path
      return unless bmp&.directory?

      bmp.children.each do |subdir|
        gain_permissions_remove(subdir)
      end
      bmp.rmdir_if_possible
    end

    sig { void }
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

    sig { void }
    def purge_caskroom_path
      odebug "Purging all staged versions of Cask #{@cask}"
      gain_permissions_remove(@cask.caskroom_path)
    end

    sig { void }
    def forbidden_tap_check
      return if Tap.allowed_taps.blank? && Tap.forbidden_taps.blank?

      owner = Homebrew::EnvConfig.forbidden_owner
      owner_contact = if (contact = Homebrew::EnvConfig.forbidden_owner_contact.presence)
        "\n#{contact}"
      end

      unless skip_cask_deps?
        cask_and_formula_dependencies.each do |cask_or_formula|
          dep_tap = cask_or_formula.tap
          next if dep_tap.blank? || (dep_tap.allowed_by_env? && !dep_tap.forbidden_by_env?)

          dep_full_name = cask_or_formula.full_name
          error_message = "The installation of #{@cask} has a dependency #{dep_full_name}\n" \
                          "from the #{dep_tap} tap but #{owner} "
          error_message << "has not allowed this tap in `$HOMEBREW_ALLOWED_TAPS`" unless dep_tap.allowed_by_env?
          error_message << " and\n" if !dep_tap.allowed_by_env? && dep_tap.forbidden_by_env?
          error_message << "has forbidden this tap in `$HOMEBREW_FORBIDDEN_TAPS`" if dep_tap.forbidden_by_env?
          error_message << ".#{owner_contact}"

          raise CaskCannotBeInstalledError.new(@cask, error_message)
        end
      end

      cask_tap = @cask.tap
      return if cask_tap.blank? || (cask_tap.allowed_by_env? && !cask_tap.forbidden_by_env?)

      error_message = "The installation of #{@cask.full_name} has the tap #{cask_tap}\n" \
                      "but #{owner} "
      error_message << "has not allowed this tap in `$HOMEBREW_ALLOWED_TAPS`" unless cask_tap.allowed_by_env?
      error_message << " and\n" if !cask_tap.allowed_by_env? && cask_tap.forbidden_by_env?
      error_message << "has forbidden this tap in `$HOMEBREW_FORBIDDEN_TAPS`" if cask_tap.forbidden_by_env?
      error_message << ".#{owner_contact}"

      raise CaskCannotBeInstalledError.new(@cask, error_message)
    end

    sig { void }
    def forbidden_cask_and_formula_check
      forbid_casks = Homebrew::EnvConfig.forbid_casks?
      forbidden_formulae = Set.new(Homebrew::EnvConfig.forbidden_formulae.to_s.split)
      forbidden_casks = Set.new(Homebrew::EnvConfig.forbidden_casks.to_s.split)
      return if !forbid_casks && forbidden_formulae.blank? && forbidden_casks.blank?

      owner = Homebrew::EnvConfig.forbidden_owner
      owner_contact = if (contact = Homebrew::EnvConfig.forbidden_owner_contact.presence)
        "\n#{contact}"
      end

      unless skip_cask_deps?
        cask_and_formula_dependencies.each do |dep_cask_or_formula|
          dep_name, dep_type, variable = if dep_cask_or_formula.is_a?(Cask) && forbidden_casks.present?
            dep_cask = dep_cask_or_formula
            env_variable = "HOMEBREW_FORBIDDEN_CASKS"
            dep_cask_name = if forbid_casks
              env_variable = "HOMEBREW_FORBID_CASKS"
              dep_cask.token
            elsif forbidden_casks.include?(dep_cask.full_name)
              dep_cask.token
            elsif dep_cask.tap.present? &&
                  forbidden_casks.include?(dep_cask.full_name)
              dep_cask.full_name
            end
            [dep_cask_name, "cask", env_variable]
          elsif dep_cask_or_formula.is_a?(Formula) && forbidden_formulae.present?
            dep_formula = dep_cask_or_formula
            formula_name = if forbidden_formulae.include?(dep_formula.name)
              dep_formula.name
            elsif dep_formula.tap.present? &&
                  forbidden_formulae.include?(dep_formula.full_name)
              dep_formula.full_name
            end
            [formula_name, "formula", "HOMEBREW_FORBIDDEN_FORMULAE"]
          end
          next if dep_name.blank?

          raise CaskCannotBeInstalledError.new(@cask, <<~EOS
            has a dependency #{dep_name} but the
            #{dep_name} #{dep_type} was forbidden for installation by #{owner} in `#{variable}`.#{owner_contact}
          EOS
          )
        end
      end
      return if !forbid_casks && forbidden_casks.blank?

      variable = "HOMEBREW_FORBIDDEN_CASKS"
      if forbid_casks
        variable = "HOMEBREW_FORBID_CASKS"
        @cask.token
      elsif forbidden_casks.include?(@cask.token)
        @cask.token
      elsif forbidden_casks.include?(@cask.full_name)
        @cask.full_name
      else
        return
      end

      raise CaskCannotBeInstalledError.new(@cask, <<~EOS
        forbidden for installation by #{owner} in `#{variable}`.#{owner_contact}
      EOS
      )
    end

    sig { void }
    def forbidden_cask_artifacts_check
      forbidden_artifacts = Set.new(Homebrew::EnvConfig.forbidden_cask_artifacts.to_s.split)
      return if forbidden_artifacts.blank?

      owner = Homebrew::EnvConfig.forbidden_owner
      owner_contact = if (contact = Homebrew::EnvConfig.forbidden_owner_contact.presence)
        "\n#{contact}"
      end

      artifacts.each do |artifact|
        # Get the artifact class name (e.g., "Pkg", "Installer", "App")
        artifact_name = artifact.class.name
        next if artifact_name.nil?

        artifact_type = artifact_name.split("::").last&.downcase
        next if artifact_type.nil?

        next unless forbidden_artifacts.include?(artifact_type)

        raise CaskCannotBeInstalledError.new(@cask, <<~EOS
          contains a '#{artifact_type}' artifact, which is forbidden for installation by #{owner} in `HOMEBREW_FORBIDDEN_CASK_ARTIFACTS`.#{owner_contact}
        EOS
        )
      end
    end

    sig { void }
    def prelude
      return if @ran_prelude

      check_deprecate_disable
      check_conflicts

      @ran_prelude = true
    end

    sig { void }
    def enqueue_downloads
      download_queue = @download_queue

      # FIXME: We need to load Cask source before enqueuing to support
      # language-specific URLs, but this will block the main process.
      if cask_from_source_api?
        if @cask.languages.any?
          load_cask_from_source_api!
        else
          Homebrew::API::Cask.source_download(@cask, download_queue:, enqueue: true)
        end
      end

      download_queue.enqueue(downloader)
    end

    private

    # load the same cask file that was used for installation, if possible
    sig { void }
    def load_installed_caskfile!
      Migrator.migrate_if_needed(@cask)

      installed_caskfile = @cask.installed_caskfile

      if installed_caskfile&.exist?
        begin
          @cask = CaskLoader.load_from_installed_caskfile(installed_caskfile)
          return
        rescue CaskInvalidError, CaskUnavailableError
          # could be caused by trying to load outdated or deleted caskfile
        end
      end

      load_cask_from_source_api! if cask_from_source_api?
      # otherwise we default to the current cask
    end

    sig { void }
    def load_cask_from_source_api!
      @cask = Homebrew::API::Cask.source_download_cask(@cask)
    end

    sig { returns(T::Boolean) }
    def cask_from_source_api?
      @cask.loaded_from_api? && @cask.caskfile_only?
    end
  end
end

require "extend/os/cask/installer"
