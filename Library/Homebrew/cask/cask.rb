# typed: strict
# frozen_string_literal: true

require "bundle_version"
require "cask/cask_loader"
require "cask/config"
require "cask/dsl"
require "cask/metadata"
require "cask/tab"
require "utils/output"
require "api_hashable"

module Cask
  # An instance of a cask.
  class Cask
    extend Forwardable
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

    sig { returns(T::Boolean) }
    attr_accessor :allow_reassignment

    sig { params(eval_all: T::Boolean).returns(T::Array[Cask]) }
    def self.all(eval_all: false)
      if !eval_all && !Homebrew::EnvConfig.eval_all?
        raise ArgumentError, "Cask::Cask#all cannot be used without `--eval-all` or `HOMEBREW_EVAL_ALL=1`"
      end

      # Load core casks from tokens so they load from the API when the core cask is not tapped.
      tokens_and_files = CoreCaskTap.instance.cask_tokens
      tokens_and_files += Tap.reject(&:core_cask_tap?).flat_map(&:cask_files)
      tokens_and_files.filter_map do |token_or_file|
        CaskLoader.load(token_or_file)
      rescue CaskUnreadableError => e
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
        api_source:               T.nilable(T::Hash[String, T.untyped]),
        config:                   T.nilable(Config),
        allow_reassignment:       T::Boolean,
        loader:                   T.nilable(CaskLoader::ILoader),
        block:                    T.nilable(T.proc.bind(DSL).void),
      ).void
    }
    def initialize(token, sourcefile_path: nil, source: nil, tap: nil, loaded_from_api: false,
                   loaded_from_internal_api: false, api_source: nil, config: nil, allow_reassignment: false,
                   loader: nil, &block)
      @token = token
      @sourcefile_path = sourcefile_path
      @source = source
      @tap = tap
      @allow_reassignment = allow_reassignment
      @loaded_from_api = loaded_from_api
      @loaded_from_internal_api = loaded_from_internal_api
      @api_source = api_source
      @loader = loader
      # Sorbet has trouble with bound procs assigned to instance variables:
      # https://github.com/sorbet/sorbet/issues/6843
      @block = T.let(block, T.untyped)

      @default_config = T.let(config || Config.new, Config)

      @config = T.let(if config_path.exist?
                        Config.from_json(File.read(config_path), ignore_invalid_keys: true)
                      else
                        @default_config
      end, Config)
      refresh
    end

    sig { returns(T::Boolean) }
    def loaded_from_api? = @loaded_from_api

    sig { returns(T::Boolean) }
    def loaded_from_internal_api? = @loaded_from_internal_api

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_reader :api_source

    # An old name for the cask.
    sig { returns(T::Array[String]) }
    def old_tokens
      @old_tokens ||= T.let(
        if (t = tap)
          Tap.tap_migration_oldnames(t, token) +
            t.cask_reverse_renames.fetch(token, [])
        else
          []
        end,
        T.nilable(T::Array[String]),
      )
    end

    sig { params(config: Config).void }
    def config=(config)
      @config = config

      refresh
    end

    sig { void }
    def refresh
      @dsl = T.let(DSL.new(self), T.nilable(DSL))
      @contains_os_specific_artifacts = nil
      return unless @block

      dsl!.instance_eval(&@block)
      dsl!.add_implicit_macos_dependency
      dsl!.language_eval
    rescue NoMethodError => e
      raise CaskInvalidError.new(token, e.message), e.backtrace
    end

    def_delegators :@dsl, *::Cask::DSL::DSL_METHODS

    sig { returns(DSL::Caveats) }
    def caveats_object = dsl!.caveats_object

    sig { params(caskroom_path: Pathname).returns(T::Array[[String, String]]) }
    def timestamped_versions(caskroom_path: self.caskroom_path)
      pattern = metadata_timestamped_path(version: "*", timestamp: "*", caskroom_path:).to_s
      relative_paths = Pathname.glob(pattern)
                               .map { |p| p.relative_path_from(p.parent.parent) }
      # Sorbet is unaware that Pathname is sortable: https://github.com/sorbet/sorbet/issues/6844
      T.unsafe(relative_paths).sort_by(&:basename) # sort by timestamp
       .map { |p| p.split.map(&:to_s) }
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
    def font?
      artifacts.all?(Artifact::Font)
    end

    sig { returns(T::Boolean) }
    def supports_linux?
      return true if font?

      # Bare `depends_on :macos` explicitly marks a cask as macOS-only
      return false if (macos_requirement = depends_on.macos) && !macos_requirement.version_specified?

      # Cache the os value before contains_os_specific_artifacts? refreshes the cask
      # (the refresh clears @dsl.os in generic/non-OS-specific contexts)
      os_value = dsl!.os

      return false if contains_os_specific_artifacts?

      # Casks with OS-specific blocks rely on the os stanza for Linux support
      return os_value.present? if dsl!.on_os_blocks_exist?

      # Platform-agnostic casks: reject macOS-only artifacts and manual installers
      artifacts.none? do |a|
        Artifact::MACOS_ONLY_ARTIFACTS.include?(a.class) ||
          (a.is_a?(Artifact::Installer) && a.manual_install)
      end
    end

    sig { returns(T::Boolean) }
    def contains_os_specific_artifacts?
      return false unless @dsl&.on_system_blocks_exist?

      return @contains_os_specific_artifacts unless @contains_os_specific_artifacts.nil?

      any_loaded = T.let(false, T::Boolean)
      OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
        Homebrew::SimulateSystem.with_tag(bottle_tag) do
          refresh

          any_loaded = true if artifacts.any? do |artifact|
            (bottle_tag.linux? && ::Cask::Artifact::MACOS_ONLY_ARTIFACTS.include?(artifact.class)) ||
            (bottle_tag.macos? && ::Cask::Artifact::LINUX_ONLY_ARTIFACTS.include?(artifact.class))
          end
        end
      rescue CaskInvalidError
        # Invalid for this OS/arch tag; treat as having no OS-specific artifacts.
        next
      ensure
        refresh
      end

      @contains_os_specific_artifacts = T.let(any_loaded, T.nilable(T::Boolean))
      any_loaded
    end

    # The caskfile is needed during installation when there are
    # `*flight` blocks or the cask has multiple languages
    sig { returns(T::Boolean) }
    def caskfile_only?
      languages.any? || artifacts.any?(Artifact::AbstractFlightBlock)
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
      installed_caskroom_path = caskroom_path
      installed_token = token

      # Check if the cask is installed with an old name.
      old_tokens.each do |old_token|
        old_caskroom_path = Caskroom.path/old_token
        next if !old_caskroom_path.directory? || old_caskroom_path.symlink?

        installed_caskroom_path = old_caskroom_path
        installed_token = old_token
        break
      end

      installed_version = timestamped_versions(caskroom_path: installed_caskroom_path).last
      return unless installed_version

      caskfile_dir = metadata_main_container_path(caskroom_path: installed_caskroom_path)
                     .join(*installed_version, "Casks")

      ["internal.json", "json", "rb"]
        .map { |ext| caskfile_dir.join("#{installed_token}.#{ext}") }
        .find(&:exist?)
    end

    sig { returns(T.nilable(String)) }
    def installed_version
      return unless (installed_caskfile = self.installed_caskfile)

      # <caskroom_path>/.metadata/<version>/<timestamp>/Casks/<token>.{rb,json} -> <version>
      installed_caskfile.dirname.dirname.dirname.basename.to_s
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
      return false if (url = self.url).nil?

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
      @new_download_sha ||= T.let(
        Installer.new(self, verify_download_integrity: false)
                 .download(quiet: true)
                 .instance_eval { |x| Digest::SHA256.file(x).hexdigest },
        T.nilable(String),
      )
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
      params(greedy: T::Boolean, greedy_latest: T.nilable(T::Boolean), greedy_auto_updates: T.nilable(T::Boolean))
        .returns(T::Boolean)
    }
    def outdated?(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      !outdated_version(greedy:, greedy_latest:,
                        greedy_auto_updates:).nil?
    end

    sig {
      params(greedy: T::Boolean, greedy_latest: T.nilable(T::Boolean), greedy_auto_updates: T.nilable(T::Boolean))
        .returns(T.nilable(String))
    }
    def outdated_version(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      # special case: tap version is not available
      return if version.nil?

      if version.latest?
        return installed_version if (greedy || greedy_latest) && outdated_download_sha?

        return
      end

      return if installed_version == version

      if auto_updates && !greedy && !greedy_auto_updates
        return installed_version if auto_updates_bundle_outdated?

        return
      end

      installed_version
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
        }
      else
        "#{token} (#{installed_version}) != #{version}"
      end
    end

    sig { returns(T.nilable(String)) }
    def ruby_source_path
      return @ruby_source_path if defined?(@ruby_source_path)

      return unless (sfp = sourcefile_path)
      return unless (t = tap)

      @ruby_source_path = T.let(sfp.relative_path_from(t.path).to_s, T.nilable(String))
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def ruby_source_checksum
      @ruby_source_checksum ||= T.let(
        begin
          sfp = sourcefile_path
          {
            sha256: sfp ? Digest::SHA256.file(sfp).hexdigest : nil,
          }.freeze
        end,
        T.nilable(T::Hash[Symbol, T.nilable(String)]),
      )
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
        "outdated"                        => outdated?,
        "sha256"                          => sha256,
        "artifacts"                       => artifacts_list,
        "caveats"                         => caveats_for_api,
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

    HASH_KEYS_TO_SKIP = T.let(%w[outdated installed versions].freeze, T::Array[String])
    private_constant :HASH_KEYS_TO_SKIP

    AUTO_UPDATES_BAD_BUNDLE_VERSIONS = %w[0 0.0].freeze
    private_constant :AUTO_UPDATES_BAD_BUNDLE_VERSIONS

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash_with_variations
      if loaded_from_internal_api?
        raise UsageError, "Cannot call #to_hash_with_variations on casks loaded from the internal API"
      end

      if loaded_from_api? && (json_cask = api_source) && !Homebrew::EnvConfig.no_install_from_api?
        return api_to_local_hash(json_cask.dup)
      end

      hash = to_h
      variations = {}

      if dsl!.on_system_blocks_exist?
        begin
          OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
            next if bottle_tag.linux? && dsl!.os.nil?
            next if bottle_tag.macos? &&
                    depends_on.macos &&
                    !dsl!.depends_on_set_in_block? &&
                    !depends_on.macos.allows?(bottle_tag.to_macos_version)

            Homebrew::SimulateSystem.with_tag(bottle_tag) do
              refresh

              to_h.each do |key, value|
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
      end

      hash["variations"] = variations
      hash
    end

    sig { params(uninstall_only: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def artifacts_list(uninstall_only: false)
      artifacts.filter_map do |artifact|
        case artifact
        when Artifact::AbstractFlightBlock
          uninstall_flight_block = artifact.directives.key?(:uninstall_preflight) ||
                                   artifact.directives.key?(:uninstall_postflight)
          next if uninstall_only && !uninstall_flight_block

          # Only indicate whether this block is used as we don't load it from the API
          { artifact.summarize.to_sym => nil }
        else
          zap_artifact = artifact.is_a?(Artifact::Zap)
          uninstall_artifact = artifact.respond_to?(:uninstall_phase) || artifact.respond_to?(:post_uninstall_phase)
          next if uninstall_only && !zap_artifact && !uninstall_artifact

          { artifact.class.dsl_key => artifact.to_args }
        end
      end
    end

    sig { params(uninstall_only: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def rename_list(uninstall_only: false)
      rename.filter_map do |rename|
        { from: rename.from, to: rename.to }
      end
    end

    private

    # Returns caveats text for API serialization, excluding conditional
    # built-in caveats that depend on the current machine's state.
    # These are stored as separate boolean fields (e.g. caveats_rosetta)
    # and evaluated at install time instead.
    sig { returns(T.nilable(String)) }
    def caveats_for_api
      Tty.strip_ansi(caveats_object.to_s_without_conditional)
         .presence
    end

    sig { returns(T.nilable(Homebrew::BundleVersion)) }
    def bundle_version
      @bundle_version ||= T.let(
        if (bundle = artifacts.find { |a| a.is_a?(Artifact::App) }&.target) &&
           (plist = Pathname("#{bundle}/Contents/Info.plist")) && plist.exist? && plist.readable?
          Homebrew::BundleVersion.from_info_plist(plist)
        end,
        T.nilable(Homebrew::BundleVersion),
      )
    end

    sig { returns(DSL) }
    def dsl!
      @dsl || raise("unexpected nil @dsl")
    end

    sig { returns(T.nilable(Artifact::App)) }
    def single_app_artifact
      app_artifacts = artifacts.grep(Artifact::App)
      return unless app_artifacts.one?

      app_artifacts.first
    end

    sig { returns(T.nilable(Pathname)) }
    def installed_app_info_plist
      return unless (app_artifact = single_app_artifact)

      info_plist = app_artifact.target/"Contents/Info.plist"
      info_plist if info_plist.exist? && info_plist.readable?
    end

    sig { params(first: T.nilable(String), second: T.nilable(String)).returns(T.nilable(Integer)) }
    def compare_version_strings(first, second)
      return if first.blank? || second.blank?
      return if first.split(".").size != second.split(".").size

      Version.new(first) <=> Version.new(second)
    rescue
      nil
    end

    sig { returns(T::Boolean) }
    def auto_updates_bundle_outdated?
      return false unless Homebrew::EnvConfig.upgrade_auto_updates_casks?
      return false if !auto_updates || version.latest?
      return false unless installed_app_info_plist

      tap_short_version = version.csv.first.to_s.presence || version.to_s

      begin
        installed_short_version = bundle_short_version
        installed_bundle_version = bundle_long_version
      rescue ErrorDuringExecution
        return false
      end
      installed_bundle_version = nil if AUTO_UPDATES_BAD_BUNDLE_VERSIONS.include?(installed_bundle_version)
      installed_short_version = nil if AUTO_UPDATES_BAD_BUNDLE_VERSIONS.include?(installed_short_version)
      return false if installed_short_version.nil? && installed_bundle_version.nil?

      return false if [installed_short_version, installed_bundle_version].any? do |installed_plist_version|
        compare_version_strings(installed_plist_version, tap_short_version)&.zero?
      end

      short_comparison = compare_version_strings(installed_short_version, tap_short_version)
      return true if short_comparison == -1
      return false if short_comparison == 1

      build_comparisons = version.csv.filter_map do |candidate|
        compare_version_strings(installed_bundle_version, candidate.to_s)
      end
      return false if build_comparisons.empty?
      return false if build_comparisons.include?(0)

      build_comparisons.include?(-1)
    end

    sig { params(hash: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def api_to_local_hash(hash)
      hash["token"] = token
      hash["installed"] = installed_version
      hash["outdated"] = outdated?
      hash
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
