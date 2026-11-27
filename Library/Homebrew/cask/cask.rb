# typed: strict
# frozen_string_literal: true

require "bundle_version"
require "cask/cask_base"
require "cask/cask_loader"
require "cask/config"
require "cask/dsl"
require "cask/metadata"
require "cask/tab"
require "utils/output"
require "utils/path"
require "api_hashable"
require "trust"
require "tmpdir"

module Cask
  # An instance of a cask.
  class Cask
    extend APIHashable
    extend ::Utils::Output::Mixin
    include Metadata

    # The unique identifier for this {Cask}, used to refer to it in commands
    # and tap paths.
    # e.g. `firefox`
    #
    # @api public
    sig { returns(String) }
    attr_reader :token

    # The configuration of this {Cask}.
    #
    # @api internal
    sig { returns(Config) }
    attr_reader :config

    sig { returns(T.nilable(Pathname)) }
    attr_reader :sourcefile_path

    sig { returns(T.nilable(String)) }
    attr_reader :source

    sig { returns(Config) }
    attr_reader :default_config

    sig { returns(T.nilable(CaskLoader::ILoader)) }
    attr_reader :loader

    sig { returns(T.nilable(Pathname)) }
    attr_accessor :download

    sig { params(temp: T.nilable(Pathname)).void }
    attr_writer :temp

    # Private temporary storage for the current cask lifecycle operation.
    # @api internal
    sig { returns(Pathname) }
    def temp
      @temp ||= Pathname(Dir.mktmpdir("cask-#{token}-", HOMEBREW_TEMP))
    end

    # Retain files on failure so an incomplete restoration cannot lose data.
    # @api internal
    sig { params(retain: T::Boolean).void }
    def cleanup_temp(retain: false)
      temporary = @temp
      @temp = nil
      return unless temporary&.exist?

      if retain
        ::Utils::Output.opoo "Temporary files retained at:\n#{temporary}"
      else
        FileUtils.remove_entry_secure(temporary)
      end
    end

    sig { returns(T::Boolean) }
    attr_accessor :allow_reassignment

    sig { params(core_tokens: T::Array[String]).returns(T::Array[Cask]) }
    def self.all(core_tokens: CoreCaskTap.instance.cask_tokens)
      # Load core casks from tokens so they load from the API when the core cask is not tapped.
      tokens_and_files = core_tokens
      tokens_and_files += Tap.reject(&:core_cask_tap?)
                             .flat_map(&:cask_files)
                             .then { |files| Homebrew::Trust.trusted_cask_files(files) }
      tokens_and_files.filter_map do |token_or_file|
        if token_or_file.is_a?(String)
          CaskLoader.load_from_name(token_or_file)
        else
          CaskLoader.from_path(token_or_file)
        end
      rescue CaskUnavailableError, CaskInvalidError => e
        # Don't let one broken cask break commands. But do complain.
        opoo e.message

        nil
      end
    end

    # This collides with Kernel#tap, complicating the type signature.
    # Overload sigs are not supported by Sorbet, otherwise we would use:
    #   sig { params(blk: T.proc.params(arg0: Cask).void).returns(T.self_type) }
    #   sig { params(blk: NilClass).returns(T.nilable(Tap)) }
    # Using a union type would require casts or type guards at call sites,
    # so T.untyped is used as the return type instead.
    sig { params(blk: T.nilable(T.proc.params(arg0: Cask).void)).returns(T.untyped) }
    def tap(&blk)
      return super if block_given? # Kernel#tap

      @tap
    end

    sig {
      params(
        token:                    String,
        sourcefile_path:          T.nilable(Pathname),
        source:                   T.nilable(String),
        tap:                      T.nilable(Tap),
        loaded_from_api:          T::Boolean,
        loaded_from_internal_api: T::Boolean,
        loaded_from_metadata:     T::Boolean,
        api_source:               T.nilable(T::Hash[String, T.untyped]),
        config:                   T.nilable(Config),
        allow_reassignment:       T::Boolean,
        loader:                   T.nilable(CaskLoader::ILoader),
        block:                    T.nilable(T.proc.bind(DSL).void),
      ).void
    }
    def initialize(token, sourcefile_path: nil, source: nil, tap: nil, loaded_from_api: false,
                   loaded_from_internal_api: false, loaded_from_metadata: false, api_source: nil, config: nil,
                   allow_reassignment: false, loader: nil, &block)
      @old_tokens = T.let(nil, T.nilable(T::Array[String]))
      @new_download_sha = T.let(nil, T.nilable(String))
      @ruby_source_checksum = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(String)]))

      @token = token
      @sourcefile_path = sourcefile_path
      @source = source
      @tap = tap
      @allow_reassignment = allow_reassignment
      @loaded_from_api = loaded_from_api
      @loaded_from_internal_api = loaded_from_internal_api
      @loaded_from_metadata = loaded_from_metadata
      @api_source = api_source
      @language_evaluator = T.let(nil, T.nilable(T.proc.params(languages: T::Array[String]).returns(T.nilable(String))))
      @loader = loader
      @temp = T.let(nil, T.nilable(Pathname))
      # Sorbet has trouble with bound procs assigned to instance variables:
      # https://github.com/sorbet/sorbet/issues/6843
      @block = T.let(block, T.untyped)

      default_config = config || Config.new
      @default_config = T.let(default_config, Config)

      resolved_config = if config_path.exist?
        Config.from_json(File.read(config_path), ignore_invalid_keys: true)
      else
        @default_config
      end
      @config = T.let(resolved_config, Config)
      refresh
    end

    sig { returns(T::Boolean) }
    def loaded_from_api? = @loaded_from_api

    sig { returns(T::Boolean) }
    def loaded_from_internal_api? = @loaded_from_internal_api

    # Whether this cask was loaded from installed metadata.
    sig { returns(T::Boolean) }
    def loaded_from_metadata? = @loaded_from_metadata

    sig { returns(T.any(String, Pathname)) }
    def reloadable_ref
      return full_name if loaded_from_api?

      sourcefile_path || raise("unexpected nil cask sourcefile_path")
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_reader :api_source

    # An old name for the cask.
    sig { returns(T::Array[String]) }
    def old_tokens
      @old_tokens ||= if (t = tap)
        Tap.tap_migration_oldnames(t, token, cask: true) +
          t.cask_reverse_renames.fetch(token, [])
      else
        []
      end
    end

    sig { params(config: Config).void }
    def config=(config)
      @config = config

      refresh
    end

    # Return an independent cask for the current system, reusing its parsed Ruby.
    # @api internal
    sig { params(config: Config).returns(Cask) }
    def refresh_copy(config: self.config)
      ENV.clear_sensitive_environment_for_eval! do
        copy = if loaded_from_metadata?
          metadata_loader = loader
          CaskLoader.load_from_installed_caskfile(
            sourcefile_path || raise("unexpected nil cask sourcefile_path"), config:,
            api_fallback: !metadata_loader.is_a?(CaskLoader::FromAPILoader) || metadata_loader.api_fallback
          )
        elsif loaded_from_api?
          CaskLoader.load(full_name, config:)
        else
          self.class.new(token, sourcefile_path:, source:, tap:, config:, allow_reassignment:, &@block)
        end
        copy.config = config unless copy.config.equal?(config)
        copy
      end
    end

    sig { void }
    def refresh
      @dsl = T.let(DSL.new(self), T.nilable(DSL))
      return unless @block

      dsl!.instance_eval(&@block)
      dsl!.language_eval
    rescue NoMethodError => e
      raise CaskInvalidError.new(token, e.message), e.backtrace
    end

    # Refresh the cask as evaluated on `tag` and yield. Returns `nil` instead of
    # raising when the cask has `on_system` blocks that omit the tag.
    sig {
      type_parameters(:U)
        .params(tag: ::Utils::Bottles::Tag, _block: T.proc.returns(T.type_parameter(:U)))
        .returns(T.nilable(T.type_parameter(:U)))
    }
    def refresh_for_tag(tag, &_block)
      Homebrew::SimulateSystem.with(os: tag.system, arch: tag.arch) do
        refresh
        yield
      end
    rescue CaskInvalidError, CaskUnreadableError
      raise unless on_system_blocks_exist?

      nil
    end

    def_delegators :@dsl, *(::Cask::DSL::DSL_METHODS - [:language])

    sig {
      params(
        args:    String,
        default: T::Boolean,
        block:   T.nilable(T.proc.returns(String)),
      ).returns(T.nilable(String))
    }
    def language(*args, default: false, &block)
      return @language_evaluator.call(config.languages) if args.empty? && block.nil? && @language_evaluator

      dsl!.language(*args, default:, &block)
    end

    sig { returns(DSL::Caveats) }
    def caveats_object = dsl!.caveats_object

    sig { params(caskroom_path: Pathname).returns(T::Array[[String, String]]) }
    def timestamped_versions(caskroom_path: self.caskroom_path)
      pattern = metadata_timestamped_path(version: "*", timestamp: "*", caskroom_path:).to_s
      Pathname.glob(pattern)
              .map { |p| p.relative_path_from(p.parent.parent) }
              .map { |p| [p.dirname.to_s, p.basename.to_s] }
              .sort_by(&:last) # sort by timestamp
    end

    # The fully-qualified token of this {Cask}.
    #
    # @api internal
    sig { returns(String) }
    def full_token
      return token if (t = tap).nil?
      return token if t.core_cask_tap?

      "#{t.name}/#{token}"
    end

    # Alias for {#full_token}.
    #
    # @api internal
    sig { returns(String) }
    def full_name = full_token

    sig { returns(T::Boolean) }
    def installed?
      installed_caskfile&.exist? || false
    end

    sig { returns(T::Boolean) }
    def any_version_installed? = installed?

    sig { returns(T::Boolean) }
    def font?
      artifacts.all?(Artifact::Font)
    end

    sig { returns(T::Boolean) }
    def installable_artifact?
      artifacts.any? do |artifact|
        artifact.respond_to?(:install_phase) || artifact.is_a?(Artifact::StageOnly)
      end
    end

    sig { returns(T::Boolean) }
    def supports_linux? = !depends_on.requires_macos?

    sig { returns(T::Boolean) }
    def supports_macos?
      !depends_on.requires_linux?
    end

    # True if this cask can be installed on this platform.
    sig { returns(T::Boolean) }
    def valid_platform?
      if Homebrew::SimulateSystem.simulating_or_running_on_macos?
        supports_macos?
      else
        supports_linux?
      end
    end

    # True if this cask doesn't support this platform.
    # Casks loaded from the internal API use the value stored there for this platform.
    sig { returns(T::Boolean) }
    def incompatible?
      return api_source&.[]("incompatible") == true if loaded_from_internal_api?

      !platform_supported?(Homebrew::SimulateSystem.current_tag)
    end

    sig { returns(T::Boolean) }
    def uninstall_flight_blocks?
      artifacts.any? do |artifact|
        case artifact
        when Artifact::PreflightBlock
          artifact.directives.key?(:uninstall_preflight)
        when Artifact::PostflightBlock
          artifact.directives.key?(:uninstall_postflight)
        end
      end
    end

    sig { returns(T.nilable(Time)) }
    def install_time
      # <caskroom_path>/.metadata/<version>/<timestamp>/Casks/<token>.{rb,json} -> <timestamp>
      caskfile = installed_caskfile
      Time.strptime(caskfile.dirname.dirname.basename.to_s, Metadata::TIMESTAMP_FORMAT) if caskfile
    end

    sig { returns(T.nilable(Pathname)) }
    def installed_caskfile
      Caskroom.cask_installed_caskfile(token, old_tokens:)
    end

    sig { returns(T.nilable(String)) }
    def installed_version
      # <caskroom_path>/.metadata/<version>/<timestamp>/Casks/<token>.{rb,json} -> <version>
      Caskroom.cask_installed_version(token, old_tokens:)
    end

    sig { void }
    def pin
      return unless (installed_version = self.installed_version)

      versioned_path = caskroom_path/installed_version
      return unless versioned_path.exist?

      HOMEBREW_PINNED_CASKS.mkpath
      return if pinned?

      pin_path.unlink if pin_path.file? || pin_path.symlink?
      pin_path.make_relative_symlink(versioned_path)
    end

    sig { void }
    def unpin
      pin_path.unlink if pin_path.symlink?
      ::Utils::Path.rmdir_if_possible(HOMEBREW_PINNED_CASKS)
    end

    sig { returns(T::Boolean) }
    def pinned?
      pin_path.symlink? && pin_path.exist?
    end

    sig { returns(T::Boolean) }
    def pinnable?
      return false unless (installed_version = self.installed_version)

      (caskroom_path/installed_version).exist?
    end

    sig { returns(T.nilable(String)) }
    def pinned_version
      ::Utils::Path.resolved_path(pin_path).basename.to_s if pinned?
    end

    sig { returns(Pathname) }
    def pin_path
      HOMEBREW_PINNED_CASKS/token
    end

    sig { returns(T.nilable(String)) }
    def bundle_short_version
      bundle_version&.short_version
    end

    sig { returns(T.nilable(String)) }
    def bundle_long_version
      bundle_version&.version
    end

    sig { returns(Tab) }
    def tab
      Tab.for_cask(self)
    end

    sig { returns(Pathname) }
    def config_path
      metadata_main_container_path/"config.json"
    end

    sig { returns(T::Boolean) }
    def checksumable?
      return false if (url = self.url).nil? || url.to_s.blank?

      DownloadStrategyDetector.detect(url.to_s, url.using) <= AbstractFileDownloadStrategy || false
    end

    sig { returns(Pathname) }
    def download_sha_path
      metadata_main_container_path/"LATEST_DOWNLOAD_SHA256"
    end

    sig { returns(String) }
    def new_download_sha
      require "cask/installer"

      # Call checksumable? before hashing
      @new_download_sha ||= Installer.new(self, verify_download_integrity: false)
                                     .download(quiet: true)
                                     .instance_eval { |x| Digest::SHA256.file(x).hexdigest }
    end

    sig { returns(T::Boolean) }
    def outdated_download_sha?
      return true unless checksumable?

      current_download_sha = download_sha_path.read if download_sha_path.exist?
      current_download_sha.blank? || current_download_sha != new_download_sha
    end

    sig { returns(Pathname) }
    def caskroom_path
      @caskroom_path ||= T.let(Caskroom.path.join(token), T.nilable(Pathname))
    end

    # Check if the installed cask is outdated.
    #
    # @api internal
    sig {
      params(
        greedy:              T::Boolean,
        greedy_latest:       T.nilable(T::Boolean),
        greedy_auto_updates: T.nilable(T::Boolean),
        minimum_version:     T.nilable(String),
      ).returns(T::Boolean)
    }
    def outdated?(greedy: false, greedy_latest: false, greedy_auto_updates: false, minimum_version: nil)
      # Disabled casks cannot be upgraded, even when a newer version is available.
      return false if disabled?

      if minimum_version.present?
        require "minimum_version"

        return Homebrew::MinimumVersion.cask_installed_below?(self, minimum_version)
      end

      !outdated_version(greedy:, greedy_latest:,
                        greedy_auto_updates:).nil?
    end

    # Whether the cask has a version that can be checked against a single self-updating app.
    sig { returns(T::Boolean) }
    def auto_updates_app?
      auto_updates == true && version.present? && !version.latest? && artifacts.one?(Artifact::App)
    end

    # Upgrade callers can handle an exact bundle match without reinstalling the app.
    sig {
      params(greedy: T::Boolean, greedy_latest: T.nilable(T::Boolean), greedy_auto_updates: T.nilable(T::Boolean),
             on_self_update: T.nilable(T.proc.params(cask: Cask, installed: Cask).void)).returns(T.nilable(String))
    }
    def outdated_version(greedy: false, greedy_latest: false, greedy_auto_updates: false, &on_self_update)
      # special case: tap version is not available
      return if version.nil?

      if version.latest?
        return installed_version if (greedy || greedy_latest) && outdated_download_sha?

        return
      end

      installed = installed_version
      return if installed.nil?

      if auto_updates_app?
        return if !greedy && !greedy_auto_updates && !Homebrew::EnvConfig.upgrade_auto_updates_casks?
        return installed if auto_updates_bundle_outdated?(installed, &on_self_update)
      elsif installed != version && (!auto_updates || greedy || greedy_auto_updates)
        return installed
      end

      nil
    end

    sig {
      params(
        greedy:              T::Boolean,
        verbose:             T::Boolean,
        json:                T::Boolean,
        greedy_latest:       T::Boolean,
        greedy_auto_updates: T::Boolean,
      ).returns(T.any(String, T::Hash[Symbol, T.untyped]))
    }
    def outdated_info(greedy, verbose, json, greedy_latest, greedy_auto_updates)
      return token if !verbose && !json

      installed_version = outdated_version(greedy:, greedy_latest:,
                                           greedy_auto_updates:).to_s

      if json
        {
          name:               token,
          installed_versions: [installed_version],
          current_version:    version,
          pinned:             pinned?,
          pinned_version:,
        }
      else
        pinned = " [pinned at #{pinned_version}]" if pinned?

        "#{token} (#{installed_version}) != #{version}#{pinned}"
      end
    end

    sig { returns(T.nilable(String)) }
    def ruby_source_path
      return @ruby_source_path if defined?(@ruby_source_path)

      return unless (sfp = sourcefile_path)
      return unless (t = tap)

      ruby_source_path = sfp.relative_path_from(t.path).to_s
      @ruby_source_path = T.let(ruby_source_path, T.nilable(String))
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def ruby_source_checksum
      @ruby_source_checksum ||= begin
        sfp = sourcefile_path
        {
          sha256: (Digest::SHA256.file(sfp).hexdigest if sfp),
        }.freeze
      end
    end

    sig { returns(T::Array[String]) }
    def languages
      @languages ||= T.let(dsl!.languages, T.nilable(T::Array[String]))
    end

    sig { returns(T.nilable(String)) }
    def tap_git_head
      @tap_git_head ||= T.let(tap&.git_head, T.nilable(String))
    rescue TapUnavailableError
      nil
    end

    sig { params(cask_struct: Homebrew::API::CaskStruct, tap_git_head: T.nilable(String)).void }
    def populate_from_api!(cask_struct, tap_git_head:)
      raise ArgumentError, "Expected cask to be loaded from the API" unless loaded_from_api?

      @languages = cask_struct.languages
      @language_evaluator = ->(languages) { cask_struct.language(languages) }
      @tap_git_head = tap_git_head
      @ruby_source_path = cask_struct.ruby_source_path
      @ruby_source_checksum = cask_struct.ruby_source_checksum
    end

    # The string representation of this {Cask}, returning its {#token}.
    #
    # @api public
    sig { returns(String) }
    def to_s = token

    sig { returns(String) }
    def inspect
      "#<Cask #{token}#{sourcefile_path&.to_s&.prepend(" ")}>"
    end

    sig { returns(Integer) }
    def hash
      token.hash
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def eql?(other)
      instance_of?(other.class) && token == other.token
    end
    alias == eql?

    sig { returns(T::Hash[String, T.untyped]) }
    def to_h
      {
        "token"                           => token,
        "full_token"                      => full_name,
        "old_tokens"                      => old_tokens,
        "tap"                             => tap&.name,
        "name"                            => name,
        "desc"                            => desc,
        "homepage"                        => homepage,
        "url"                             => url,
        "url_specs"                       => url_specs,
        "version"                         => version,
        "autobump"                        => autobump?,
        "no_autobump_message"             => no_autobump_message,
        "skip_livecheck"                  => livecheck.skip?,
        "installed"                       => installed_version,
        "installed_time"                  => install_time&.to_i,
        "bundle_version"                  => bundle_long_version,
        "bundle_short_version"            => bundle_short_version,
        "pinned"                          => pinned?,
        "pinned_version"                  => pinned_version,
        "outdated"                        => outdated?,
        "sha256"                          => sha256,
        "artifacts"                       => artifacts_list,
        # Conditional built-in caveats depend on the current machine so are
        # stored as separate booleans (e.g. `caveats_rosetta`) instead.
        "caveats"                         => Tty.strip_ansi(caveats_object.to_s_without_conditional).presence,
        "caveats_rosetta"                 => caveats_object.invoked?(:requires_rosetta) || nil,
        "depends_on"                      => depends_on,
        "conflicts_with"                  => conflicts_with,
        "container"                       => container&.pairs,
        "rename"                          => rename_list,
        "auto_updates"                    => auto_updates,
        "deprecated"                      => deprecated?,
        "deprecation_date"                => deprecation_date,
        "deprecation_reason"              => deprecation_reason,
        "deprecation_replacement_formula" => deprecation_replacement_formula,
        "deprecation_replacement_cask"    => deprecation_replacement_cask,
        "deprecate_args"                  => deprecate_args,
        "disabled"                        => disabled?,
        "disable_date"                    => disable_date,
        "disable_reason"                  => disable_reason,
        "disable_replacement_formula"     => disable_replacement_formula,
        "disable_replacement_cask"        => disable_replacement_cask,
        "disable_args"                    => disable_args,
        "tap_git_head"                    => tap_git_head,
        "languages"                       => languages,
        "ruby_source_path"                => ruby_source_path,
        "ruby_source_checksum"            => ruby_source_checksum,
      }
    end

    HASH_KEYS_TO_SKIP = %w[outdated installed pinned pinned_version versions].freeze
    private_constant :HASH_KEYS_TO_SKIP

    AUTO_UPDATES_BAD_BUNDLE_VERSIONS = %w[0 0.0].freeze
    private_constant :AUTO_UPDATES_BAD_BUNDLE_VERSIONS

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash_with_variations
      if loaded_from_internal_api?
        raise UsageError, "Cannot call #to_hash_with_variations on casks loaded from the internal API"
      end

      if loaded_from_api? && (json_cask = api_source) && CoreCaskTap.instance.use_api?
        return json_cask.merge(
          "token"          => token,
          "installed"      => installed_version,
          "pinned"         => pinned?,
          "pinned_version" => pinned_version,
          "outdated"       => outdated?,
        )
      end

      hash = to_h_with_language_variations
      variations = {}
      supported_platforms = []
      on_system_blocks_exist = dsl!.on_system_blocks_exist?

      if on_system_blocks_exist
        begin
          OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
            macos_requirements = [depends_on.macos, depends_on.maximum_macos].compact
            next if bottle_tag.macos? &&
                    macos_requirements.present? &&
                    !dsl!.depends_on_set_in_block? &&
                    macos_requirements.any? do |requirement|
                      # Avoid recursive equality between cached version-comparison keys across casks.
                      !requirement.allows?(MacOSVersion.from_symbol(bottle_tag.system))
                    end

            refresh_for_tag(bottle_tag) do
              supported_platforms << bottle_tag.to_sym if platform_supported?(bottle_tag)

              to_h_with_language_variations.each do |key, value|
                next if HASH_KEYS_TO_SKIP.include? key
                next if value.to_s == hash[key].to_s

                variations[bottle_tag.to_sym] ||= {}
                variations[bottle_tag.to_sym][key] = value
              end
            end
          end
        ensure
          refresh
        end
      else
        supported_platforms = OnSystem::VALID_OS_ARCH_TAGS.filter_map do |bottle_tag|
          bottle_tag.to_sym if platform_supported?(bottle_tag)
        end
      end

      hash["variations"] = variations
      hash["supported_platforms"] = supported_platforms
      hash
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_h_with_language_variations
      language_groups = dsl!.language_groups
      return to_h if language_groups.empty?

      default_language_group = dsl!.default_language_group
      raise CaskInvalidError.new(self, "No default language specified.") if default_language_group.nil?

      original_config = config
      language_hashes = language_groups.to_h do |languages|
        localised_config = original_config.dup
        localised_config.explicit = original_config.explicit.dup
        localised_config.languages = [languages.fetch(0)]
        self.config = localised_config
        [languages, [to_h, dsl!.language_eval]]
      end
      hash = language_hashes.fetch(default_language_group).first
      hash["language_variations"] = language_hashes.map do |languages, (language_hash, value)|
        variation = {
          "languages" => languages,
          "default"   => languages == default_language_group,
          "value"     => value,
        }
        language_hash.each do |key, language_value|
          next if HASH_KEYS_TO_SKIP.include? key
          next if language_value.to_s == hash[key].to_s

          variation[key] = language_value
        end
        variation
      end
      hash
    ensure
      self.config = original_config if original_config
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_installed_json_hash
      json = {}
      only_path = url&.only_path
      json["url_specs"] = { "only_path" => only_path } if only_path.present?
      uninstall_artifacts = artifacts_list(uninstall_only: true)
      if uninstall_artifacts.size < artifacts.size && auto_updates_app?
        # The receipt omits install-only stanzas such as pkg. Keep them for the next self-update comparison.
        json["artifacts"] = artifacts_list
      elsif uninstall_artifacts.empty?
        json["artifacts"] = []
      end
      json
    end

    sig { params(install_only: T::Boolean, uninstall_only: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def artifacts_list(install_only: false, uninstall_only: false)
      artifacts.filter_map do |artifact|
        case artifact
        when Artifact::AbstractFlightBlock
          uninstall_flight_block = artifact.directives.key?(:uninstall_preflight) ||
                                   artifact.directives.key?(:uninstall_postflight)
          next if install_only && uninstall_flight_block
          next if uninstall_only && !uninstall_flight_block

          # Only indicate whether this block is used as we don't load it from the API
          { artifact.summarize.to_sym => nil }
        else
          next if install_only && !artifact.respond_to?(:install_phase)

          zap_artifact = artifact.is_a?(Artifact::Zap)
          uninstall_artifact = artifact.respond_to?(:uninstall_phase) || artifact.respond_to?(:post_uninstall_phase)
          next if uninstall_only && !zap_artifact && !uninstall_artifact

          entry = T.let(
            { artifact.class.dsl_key => artifact.to_args },
            T::Hash[Symbol, T.any(String, T::Array[T.anything])],
          )
          entry[:target] = artifact.target.to_s if !uninstall_only && artifact.is_a?(Artifact::Relocated)
          entry
        end
      end
    end

    sig { params(uninstall_only: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def rename_list(uninstall_only: false)
      rename.filter_map do |rename|
        { from: rename.from, to: rename.to }
      end
    end

    sig { params(bottle_tag: ::Utils::Bottles::Tag, installable: T::Boolean).returns(T::Boolean) }
    def platform_supported?(bottle_tag, installable: true)
      return false if version.blank? || sha256.blank? || url.blank?
      return false if installable && !installable_artifact?

      meets_platform_requirements?(bottle_tag)
    end

    # Whether the cask's OS, macOS version and architecture requirements allow this platform.
    sig { params(bottle_tag: ::Utils::Bottles::Tag).returns(T::Boolean) }
    def meets_platform_requirements?(bottle_tag)
      if bottle_tag.linux?
        return false unless supports_linux?
      else
        return false unless supports_macos?
      end

      arch_supported = depends_on.arch&.any? do |arch|
        required_arch = ::Utils::Bottles::Tag.new(system: bottle_tag.system, arch: arch[:type]).standardized_arch
        required_arch == bottle_tag.standardized_arch
      end
      return false if arch_supported == false

      return true unless bottle_tag.macos?

      [depends_on.macos, depends_on.maximum_macos].compact.all? do |requirement|
        requirement.allows?(bottle_tag.to_macos_version)
      end
    end

    private

    sig { returns(T.nilable(Homebrew::BundleVersion)) }
    def bundle_version
      return @bundle_version if @bundle_version

      bundle_version = if (bundle = artifacts.find { |a| a.is_a?(Artifact::App) }&.target) &&
                          (plist = Pathname("#{bundle}/Contents/Info.plist")) && plist.exist? && plist.readable?
        Homebrew::BundleVersion.from_info_plist(plist)
      end
      @bundle_version = T.let(bundle_version, T.nilable(Homebrew::BundleVersion))
      bundle_version
    end

    sig { returns(DSL) }
    def dsl!
      @dsl || raise("unexpected nil @dsl")
    end

    sig { params(first: T.nilable(String), second: T.nilable(String)).returns(T.nilable(Integer)) }
    def compare_version_strings(first, second)
      return if first.blank? || second.blank?
      return if first.split(".").size != second.split(".").size

      Version.new(first) <=> Version.new(second)
    rescue
      nil
    end

    sig { params(bundle: T.nilable(String), tap: String).returns(T::Boolean) }
    def same_version_format?(bundle, tap)
      bundle&.gsub(/\d+/, "#") == tap.gsub(/\d+/, "#")
    end

    sig {
      params(installed_version: String, on_self_update: T.nilable(T.proc.params(cask: Cask, installed: Cask).void))
        .returns(T::Boolean)
    }
    def auto_updates_bundle_outdated?(installed_version, &on_self_update)
      caskfile = installed_caskfile
      return false unless caskfile

      installed_cask = begin
        CaskLoader.load_from_installed_caskfile(caskfile, api_fallback: false)
      rescue CaskInvalidError, CaskUnavailableError, MethodDeprecatedError, JSON::ParserError
        # The receipt identifies the app but can omit installation artifacts such as pkg.
        on_self_update = nil
        receipt = CaskLoader.load_installed_tab(CaskLoader.token_from_path(caskfile))
        CaskLoader.recover_from_installed_caskfile(caskfile, tab: receipt) if receipt.uninstall_artifacts.present?
      end
      return false if installed_cask.nil? || !installed_cask.artifacts.one?(Artifact::App)

      installed_short_version = installed_cask.bundle_short_version
      raw_bundle_version = installed_cask.bundle_long_version
      installed_short_version = nil if AUTO_UPDATES_BAD_BUNDLE_VERSIONS.include?(installed_short_version)
      raw_bundle_version = nil if AUTO_UPDATES_BAD_BUNDLE_VERSIONS.include?(raw_bundle_version)
      bundle_versions = [installed_short_version, raw_bundle_version].compact
      return false if bundle_versions.empty?

      exact_versions = [*bundle_versions, bundle_versions.join(","), bundle_versions.join("-")]
      tap_versions = version.csv
      tap_builds = tap_versions.drop(1)
      installed_bundle_version = raw_bundle_version
      # JetBrains apps prefix the numeric bundle build with a product code.
      if tap_builds.present? && tap_builds.all?(/\A\d+(?:\.\d+)*\z/)
        installed_bundle_version = raw_bundle_version&.sub(/\A[A-Z]+-(\d+(?:\.\d+)*)\z/, '\1')
        exact_versions << [installed_short_version, installed_bundle_version].compact.join(",") if tap_builds.one?
      end

      current_receipt = installed_version == version
      if exact_versions.include?(version)
        return false if !on_self_update || current_receipt || pinned?

        yield self, installed_cask if Version.new(installed_version) < Version.new(version)
        return false
      end

      tap_short_version = tap_versions.first.to_s.presence || version.to_s
      short_comparison = compare_version_strings(installed_short_version, tap_short_version)
      if tap_builds.present?
        # A current receipt can contain download identifiers. Require a comparable
        # release and, if it matches, a comparable build before inferring an upgrade.
        return false if current_receipt && !same_version_format?(installed_short_version, tap_short_version)

        if short_comparison&.zero?
          return false if current_receipt && !same_version_format?(installed_bundle_version, version.after_comma)

          comparisons = tap_builds.map { |build| compare_version_strings(installed_bundle_version, build) }
          return false if comparisons.intersect?([0, 1])
          return true if comparisons.all?(-1)
        end
      end

      # An exact match with the recorded short version and build identifies the cask's version scheme.
      recorded_short_version, recorded_build = installed_version.split(",")
      if recorded_build && recorded_short_version == installed_short_version &&
         [raw_bundle_version, installed_bundle_version].include?(recorded_build)
        return Version.new(installed_version) < Version.new(version)
      end

      # Some apps split a cask version like 2.61-2057 across the short
      # version and bundle version fields.
      if installed_short_version && installed_bundle_version
        combined_version_comparisons = tap_versions.filter_map do |candidate|
          compare_version_strings("#{installed_short_version}-#{installed_bundle_version}", candidate.to_s)
        end
        return false if combined_version_comparisons.include?(0)
        return false if combined_version_comparisons.present? && combined_version_comparisons.exclude?(-1)
        return false if combined_version_comparisons.empty? &&
                        installed_short_version == tap_short_version.rpartition("-").first
      end

      return false if compare_version_strings(installed_bundle_version, tap_short_version)&.zero?

      return short_comparison.negative? if short_comparison

      if tap_versions.one? && installed_short_version == installed_version
        return Version.new(installed_version) < Version.new(tap_short_version)
      end

      build_comparisons = tap_versions.filter_map do |candidate|
        compare_version_strings(installed_bundle_version, candidate.to_s)
      end
      return false if build_comparisons.include?(0)

      short_segments = installed_short_version.to_s.split(".")
      tap_segments = tap_short_version.split(".")
      # A single number may identify the build. Prefer a comparable build in that case.
      if build_comparisons.empty? || (short_segments.size > 1 && tap_segments.size > 1)
        short_segments.zip(tap_segments) do |installed, tap|
          break unless [installed, tap].all?(/\A\d+\z/)

          comparison = installed.to_i <=> tap.to_i
          return false if comparison.positive?
          return build_comparisons.all?(&:negative?) if comparison.negative?
        end
      end

      build_comparisons.include?(-1)
    rescue ErrorDuringExecution
      false
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def url_specs
      url&.specs.dup.tap do |url_specs|
        case url_specs&.dig(:user_agent)
        when :default
          url_specs.delete(:user_agent)
        when Symbol
          url_specs[:user_agent] = ":#{url_specs[:user_agent]}"
        end
      end
    end
  end
end
