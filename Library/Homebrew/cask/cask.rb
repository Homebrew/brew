# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle_version"
require "cask/cask_loader"
require "cask/config"
require "cask/dsl"
require "cask/metadata"
require "cask/tab"
require "utils/bottles"
require "extend/api_hashable"

module Cask
  # An instance of a cask.
  class Cask
    extend Forwardable
    extend APIHashable
    include Metadata

    # The token of this {Cask}.
    #
    # @api internal
    attr_reader :token

    # The configuration of this {Cask}.
    #
    # @api internal
    attr_reader :config

    attr_reader :sourcefile_path, :source, :default_config, :loader
    attr_accessor :download, :allow_reassignment

    def self.all(eval_all: false)
      if !eval_all && !Homebrew::EnvConfig.eval_all?
        raise ArgumentError, "Cask::Cask#all cannot be used without `--eval-all` or HOMEBREW_EVAL_ALL"
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

    def tap
      return super if block_given? # Object#tap

      @tap
    end

    sig {
      params(
        token:              String,
        sourcefile_path:    T.nilable(Pathname),
        source:             T.nilable(String),
        tap:                T.nilable(Tap),
        loaded_from_api:    T::Boolean,
        config:             T.nilable(Config),
        allow_reassignment: T::Boolean,
        loader:             T.nilable(CaskLoader::ILoader),
        block:              T.nilable(T.proc.bind(DSL).void),
      ).void
    }
    def initialize(token, sourcefile_path: nil, source: nil, tap: nil, loaded_from_api: false,
                   config: nil, allow_reassignment: false, loader: nil, &block)
      @token = token
      @sourcefile_path = sourcefile_path
      @source = source
      @tap = tap
      @allow_reassignment = allow_reassignment
      @loaded_from_api = loaded_from_api
      @loader = loader
      # Sorbet has trouble with bound procs assigned to instance variables:
      # https://github.com/sorbet/sorbet/issues/6843
      instance_variable_set(:@block, block)

      @default_config = config || Config.new

      self.config = if config_path.exist?
        Config.from_json(File.read(config_path), ignore_invalid_keys: true)
      else
        @default_config
      end
    end

    sig { returns(T::Boolean) }
    def loaded_from_api? = @loaded_from_api

    # An old name for the cask.
    sig { returns(T::Array[String]) }
    def old_tokens
      @old_tokens ||= if (tap = self.tap)
        Tap.tap_migration_oldnames(tap, token) +
          tap.cask_reverse_renames.fetch(token, [])
      else
        []
      end
    end

    def config=(config)
      @config = config

      refresh
    end

    def refresh
      @dsl = DSL.new(self)
      return unless @block

      @dsl.instance_eval(&@block)
      @dsl.add_implicit_macos_dependency
      @dsl.language_eval
    end

    def_delegators :@dsl, *::Cask::DSL::DSL_METHODS

    sig { params(caskroom_path: Pathname).returns(T::Array[[String, String]]) }
    def timestamped_versions(caskroom_path: self.caskroom_path)
      relative_paths = Pathname.glob(metadata_timestamped_path(
                                       version: "*", timestamp: "*",
                                       caskroom_path:
                                     ))
                               .map { |p| p.relative_path_from(p.parent.parent) }
      # Sorbet is unaware that Pathname is sortable: https://github.com/sorbet/sorbet/issues/6844
      T.unsafe(relative_paths).sort_by(&:basename) # sort by timestamp
       .map { |p| p.split.map(&:to_s) }
    end

    # The fully-qualified token of this {Cask}.
    #
    # @api internal
    def full_token
      return token if tap.nil?
      return token if tap.core_cask_tap?

      "#{tap.name}/#{token}"
    end

    # Alias for {#full_token}.
    #
    # @api internal
    def full_name = full_token

    sig { returns(T::Boolean) }
    def installed?
      installed_caskfile&.exist? || false
    end

    # The caskfile is needed during installation when there are
    # `*flight` blocks or the cask has multiple languages
    def caskfile_only?
      languages.any? || artifacts.any?(Artifact::AbstractFlightBlock)
    end

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

      ["json", "rb"]
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

    def tab
      Tab.for_cask(self)
    end

    def config_path
      metadata_main_container_path/"config.json"
    end

    def checksumable?
      return false if (url = self.url).nil?

      DownloadStrategyDetector.detect(url.to_s, url.using) <= AbstractFileDownloadStrategy
    end

    def download_sha_path
      metadata_main_container_path/"LATEST_DOWNLOAD_SHA256"
    end

    def new_download_sha
      require "cask/installer"

      # Call checksumable? before hashing
      @new_download_sha ||= Installer.new(self, verify_download_integrity: false)
                                     .download(quiet: true)
                                     .instance_eval { |x| Digest::SHA256.file(x).hexdigest }
    end

    def outdated_download_sha?
      return true unless checksumable?

      current_download_sha = download_sha_path.read if download_sha_path.exist?
      current_download_sha.blank? || current_download_sha != new_download_sha
    end

    sig { returns(Pathname) }
    def caskroom_path
      @caskroom_path ||= Caskroom.path.join(token)
    end

    # Check if the installed cask is outdated.
    #
    # @api internal
    def outdated?(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      !outdated_version(greedy:, greedy_latest:,
                        greedy_auto_updates:).nil?
    end

    def outdated_version(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      # special case: tap version is not available
      return if version.nil?

      if version.latest?
        return installed_version if (greedy || greedy_latest) && outdated_download_sha?

        return
      elsif auto_updates && !greedy && !greedy_auto_updates
        return
      end

      # not outdated unless there is a different version on tap
      return if installed_version == version

      installed_version
    end

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

    def ruby_source_path
      return @ruby_source_path if defined?(@ruby_source_path)

      return unless sourcefile_path
      return unless tap

      @ruby_source_path = sourcefile_path.relative_path_from(tap.path)
    end

    sig { returns(T::Hash[Symbol, String]) }
    def ruby_source_checksum
      @ruby_source_checksum ||= {
        sha256: Digest::SHA256.file(sourcefile_path).hexdigest,
      }.freeze
    end

    def languages
      @languages ||= @dsl.languages
    end

    def tap_git_head
      @tap_git_head ||= tap&.git_head
    rescue TapUnavailableError
      nil
    end

    def populate_from_api!(json_cask)
      raise ArgumentError, "Expected cask to be loaded from the API" unless loaded_from_api?

      @languages = json_cask.fetch(:languages, [])
      @tap_git_head = json_cask.fetch(:tap_git_head, "HEAD")

      @ruby_source_path = json_cask[:ruby_source_path]

      # TODO: Clean this up when we deprecate the current JSON API and move to the internal JSON v3.
      ruby_source_sha256 = json_cask.dig(:ruby_source_checksum, :sha256)
      ruby_source_sha256 ||= json_cask[:ruby_source_sha256]
      @ruby_source_checksum = { sha256: ruby_source_sha256 }
    end

    # @api public
    sig { returns(String) }
    def to_s = token

    sig { returns(String) }
    def inspect
      "#<Cask #{token}#{sourcefile_path&.to_s&.prepend(" ")}>"
    end

    def hash
      token.hash
    end

    def eql?(other)
      instance_of?(other.class) && token == other.token
    end
    alias == eql?

    def to_h
      {
        "token"                   => token,
        "full_token"              => full_name,
        "old_tokens"              => old_tokens,
        "tap"                     => tap&.name,
        "name"                    => name,
        "desc"                    => desc,
        "homepage"                => homepage,
        "url"                     => url,
        "url_specs"               => url_specs,
        "version"                 => version,
        "installed"               => installed_version,
        "installed_time"          => install_time&.to_i,
        "bundle_version"          => bundle_long_version,
        "bundle_short_version"    => bundle_short_version,
        "outdated"                => outdated?,
        "sha256"                  => sha256,
        "artifacts"               => artifacts_list,
        "caveats"                 => (caveats unless caveats.empty?),
        "depends_on"              => depends_on,
        "conflicts_with"          => conflicts_with,
        "container"               => container&.pairs,
        "auto_updates"            => auto_updates,
        "deprecated"              => deprecated?,
        "deprecation_date"        => deprecation_date,
        "deprecation_reason"      => deprecation_reason,
        "deprecation_replacement" => deprecation_replacement,
        "disabled"                => disabled?,
        "disable_date"            => disable_date,
        "disable_reason"          => disable_reason,
        "disable_replacement"     => disable_replacement,
        "tap_git_head"            => tap_git_head,
        "languages"               => languages,
        "ruby_source_path"        => ruby_source_path,
        "ruby_source_checksum"    => ruby_source_checksum,
      }
    end

    HASH_KEYS_TO_SKIP = %w[outdated installed versions].freeze
    private_constant :HASH_KEYS_TO_SKIP

    def to_hash_with_variations
      if loaded_from_api? && !Homebrew::EnvConfig.no_install_from_api?
        return api_to_local_hash(Homebrew::API::Cask.all_casks[token].dup)
      end

      hash = to_h
      variations = {}

      if @dsl.on_system_blocks_exist?
        begin
          MacOSVersion::SYMBOLS.keys.product(OnSystem::ARCH_OPTIONS).each do |os, arch|
            bottle_tag = ::Utils::Bottles::Tag.new(system: os, arch:)
            next unless bottle_tag.valid_combination?
            next if depends_on.macos &&
                    !@dsl.depends_on_set_in_block? &&
                    !depends_on.macos.allows?(bottle_tag.to_macos_version)

            Homebrew::SimulateSystem.with(os:, arch:) do
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

    private

    sig { returns(T.nilable(Homebrew::BundleVersion)) }
    def bundle_version
      @bundle_version ||= if (bundle = artifacts.find { |a| a.is_a?(Artifact::App) }&.target) &&
                             (plist = Pathname("#{bundle}/Contents/Info.plist")) && plist.exist? && plist.readable?
        Homebrew::BundleVersion.from_info_plist(plist)
      end
    end

    def api_to_local_hash(hash)
      hash["token"] = token
      hash["installed"] = installed_version
      hash["outdated"] = outdated?
      hash
    end

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
