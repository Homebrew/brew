# typed: true
# frozen_string_literal: true

require "attrable"
require "cask/cask_loader"
require "cask/config"
require "cask/dsl"
require "cask/metadata"
require "utils/bottles"
require "extend/api_hashable"

module Cask
  # An instance of a cask.
  #
  # @api private
  class Cask
    extend Forwardable
    extend Attrable
    extend APIHashable
    include Metadata

    attr_reader :token, :sourcefile_path, :source, :config, :default_config, :loader
    attr_accessor :download, :allow_reassignment

    attr_predicate :loaded_from_api?

    # @api private
    def self.all(eval_all: false)
      if !eval_all && !Homebrew::EnvConfig.eval_all?
        raise ArgumentError, "Cask::Cask#all cannot be used without --eval-all or HOMEBREW_EVAL_ALL"
      end

      # Load core casks from tokens so they load from the API when the core cask is not tapped.
      tokens_and_files = CoreCaskTap.instance.cask_tokens
      tokens_and_files += Tap.reject(&:core_cask_tap?).flat_map(&:cask_files)
      tokens_and_files.map do |token_or_file|
        CaskLoader.load(token_or_file)
      rescue CaskUnreadableError => e
        opoo e.message

        nil
      end.compact
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
      # Sorbet has trouble with bound procs assigned to ivars: https://github.com/sorbet/sorbet/issues/6843
      instance_variable_set(:@block, block)

      @default_config = config || Config.new

      self.config = if config_path.exist?
        Config.from_json(File.read(config_path), ignore_invalid_keys: true)
      else
        @default_config
      end
    end

    # An old name for the cask.
    sig { returns(T::Array[String]) }
    def old_tokens
      @old_tokens ||= if tap
        tap.cask_renames
           .flat_map { |old_token, new_token| (new_token == token) ? old_token : [] }
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
      @dsl.language_eval
    end

    DSL::DSL_METHODS.each do |method_name|
      define_method(method_name) { |&block| @dsl.send(method_name, &block) }
    end

    sig { params(caskroom_path: Pathname).returns(T::Array[[String, String]]) }
    def timestamped_versions(caskroom_path: self.caskroom_path)
      relative_paths = Pathname.glob(metadata_timestamped_path(
                                       version: "*", timestamp: "*",
                                       caskroom_path: caskroom_path
                                     ))
                               .map { |p| p.relative_path_from(p.parent.parent) }
      # Sorbet is unaware that Pathname is sortable: https://github.com/sorbet/sorbet/issues/6844
      T.unsafe(relative_paths).sort_by(&:basename) # sort by timestamp
       .map { |p| p.split.map(&:to_s) }
    end

    def full_name
      return token if tap.nil?
      return token if tap.core_cask_tap?

      "#{tap.name}/#{token}"
    end

    sig { returns(T::Boolean) }
    def installed?
      installed_caskfile&.exist? || false
    end

    # The caskfile is needed during installation when there are
    # `*flight` blocks or the cask has multiple languages
    def caskfile_only?
      languages.any? || artifacts.any?(Artifact::AbstractFlightBlock)
    end

    sig { returns(T.nilable(Time)) }
    def install_time
      # <caskroom_path>/.metadata/<version>/<timestamp>/Casks/<token>.{rb,json} -> <timestamp>
      time = installed_caskfile&.dirname&.dirname&.basename&.to_s
      Time.strptime(time, Metadata::TIMESTAMP_FORMAT) if time
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
      # <caskroom_path>/.metadata/<version>/<timestamp>/Casks/<token>.{rb,json} -> <version>
      installed_caskfile&.dirname&.dirname&.dirname&.basename&.to_s
    end

    def config_path
      metadata_main_container_path/"config.json"
    end

    def checksumable?
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

    def outdated?(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      !outdated_version(greedy: greedy, greedy_latest: greedy_latest,
                        greedy_auto_updates: greedy_auto_updates).nil?
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

      installed_version = outdated_version(greedy: greedy, greedy_latest: greedy_latest,
                                           greedy_auto_updates: greedy_auto_updates).to_s

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

    def ruby_source_checksum
      @ruby_source_checksum ||= {
        "sha256" => Digest::SHA256.file(sourcefile_path).hexdigest,
      }.freeze
    end

    def languages
      @languages ||= @dsl.languages
    end

    def tap_git_head
      @tap_git_head ||= tap&.git_head
    end

    def populate_from_api!(json_cask)
      raise ArgumentError, "Expected cask to be loaded from the API" unless loaded_from_api?

      @languages = json_cask.fetch(:languages, [])
      @tap_git_head = json_cask.fetch(:tap_git_head, "HEAD")

      @ruby_source_path = json_cask[:ruby_source_path]
      @ruby_source_checksum = json_cask[:ruby_source_checksum].freeze
    end

    def to_s
      @token
    end

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
      url_specs = url&.specs.dup
      case url_specs&.dig(:user_agent)
      when :default
        url_specs.delete(:user_agent)
      when Symbol
        url_specs[:user_agent] = ":#{url_specs[:user_agent]}"
      end

      {
        "token"                => token,
        "full_token"           => full_name,
        "old_tokens"           => old_tokens,
        "tap"                  => tap&.name,
        "name"                 => name,
        "desc"                 => desc,
        "homepage"             => homepage,
        "url"                  => url,
        "url_specs"            => url_specs,
        "appcast"              => appcast,
        "version"              => version,
        "installed"            => installed_version,
        "installed_time"       => install_time&.to_i,
        "outdated"             => outdated?,
        "sha256"               => sha256,
        "artifacts"            => artifacts_list,
        "caveats"              => (caveats unless caveats.empty?),
        "depends_on"           => depends_on,
        "conflicts_with"       => conflicts_with,
        "container"            => container&.pairs,
        "auto_updates"         => auto_updates,
        "deprecated"           => deprecated?,
        "deprecation_date"     => deprecation_date,
        "deprecation_reason"   => deprecation_reason,
        "disabled"             => disabled?,
        "disable_date"         => disable_date,
        "disable_reason"       => disable_reason,
        "tap_git_head"         => tap_git_head,
        "languages"            => languages,
        "ruby_source_path"     => ruby_source_path,
        "ruby_source_checksum" => ruby_source_checksum,
      }
    end

    def to_hash_with_variations
      if loaded_from_api? && !Homebrew::EnvConfig.no_install_from_api?
        return api_to_local_hash(Homebrew::API::Cask.all_casks[token])
      end

      hash = to_h
      variations = {}

      hash_keys_to_skip = %w[outdated installed versions]

      if @dsl.on_system_blocks_exist?
        begin
          MacOSVersion::SYMBOLS.keys.product(OnSystem::ARCH_OPTIONS).each do |os, arch|
            bottle_tag = ::Utils::Bottles::Tag.new(system: os, arch: arch)
            next unless bottle_tag.valid_combination?

            Homebrew::SimulateSystem.with os: os, arch: arch do
              refresh

              to_h.each do |key, value|
                next if hash_keys_to_skip.include? key
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

    private

    def api_to_local_hash(hash)
      hash["token"] = token
      hash["installed"] = installed_version
      hash["outdated"] = outdated?
      hash
    end

    def artifacts_list
      artifacts.map do |artifact|
        case artifact
        when Artifact::AbstractFlightBlock
          # Only indicate whether this block is used as we don't load it from the API
          { artifact.summarize => nil }
        else
          { artifact.class.dsl_key => artifact.to_args }
        end
      end
    end
  end
end
