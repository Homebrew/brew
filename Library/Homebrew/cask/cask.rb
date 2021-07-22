# typed: false
# frozen_string_literal: true

require "cask/cask_loader"
require "cask/config"
require "cask/dsl"
require "cask/metadata"
require "searchable"

module Cask
  # An instance of a cask.
  #
  # @api private
  class Cask
    extend T::Sig

    extend Enumerable
    extend Forwardable
    extend Searchable
    include Metadata

    attr_reader :token, :sourcefile_path, :config, :default_config

    def self.each(&block)
      return to_enum unless block

      Tap.flat_map(&:cask_files).each do |f|
        block.call CaskLoader::FromTapPathLoader.new(f).load(config: nil)
      rescue CaskUnreadableError => e
        opoo e.message
      end
    end

    def tap
      return super if block_given? # Object#tap

      @tap
    end

    def initialize(token, sourcefile_path: nil, tap: nil, config: nil, &block)
      @token = token
      @sourcefile_path = sourcefile_path
      @tap = tap
      @block = block

      @default_config = config || Config.new

      self.config = if config_path.exist?
        Config.from_json(File.read(config_path), ignore_invalid_keys: true)
      else
        @default_config
      end
    end

    def config=(config)
      @config = config

      @dsl = DSL.new(self)
      return unless @block

      @dsl.instance_eval(&@block)
      @dsl.language_eval
    end

    DSL::DSL_METHODS.each do |method_name|
      define_method(method_name) { |&block| @dsl.send(method_name, &block) }
    end

    sig { returns(T::Array[[String, String]]) }
    def timestamped_versions
      Pathname.glob(metadata_timestamped_path(version: "*", timestamp: "*"))
              .map { |p| p.relative_path_from(p.parent.parent) }
              .sort_by(&:basename) # sort by timestamp
              .map { |p| p.split.map(&:to_s) }
    end

    def versions
      timestamped_versions.map(&:first)
                          .reverse
                          .uniq
                          .reverse
    end

    def full_name
      return token if tap.nil?
      return token if tap.user == "Homebrew"

      "#{tap.name}/#{token}"
    end

    def installed?
      !versions.empty?
    end

    sig { returns(T.nilable(Time)) }
    def install_time
      _, time = timestamped_versions.last
      return unless time

      Time.strptime(time, Metadata::TIMESTAMP_FORMAT)
    end

    def installed_caskfile
      installed_version = timestamped_versions.last
      metadata_main_container_path.join(*installed_version, "Casks", "#{token}.rb")
    end

    def config_path
      metadata_main_container_path/"config.json"
    end

    def caskroom_path
      @caskroom_path ||= Caskroom.path.join(token)
    end

    def outdated?(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      !outdated_versions(greedy: greedy, greedy_latest: greedy_latest,
                         greedy_auto_updates: greedy_auto_updates).empty?
    end

    def outdated_versions(greedy: false, greedy_latest: false, greedy_auto_updates: false)
      # special case: tap version is not available
      return [] if version.nil?

      if greedy || (greedy_latest && greedy_auto_updates) || (greedy_auto_updates && auto_updates)
        return versions if version.latest?
      elsif greedy_latest && version.latest?
        return versions
      elsif auto_updates
        return []
      end

      installed = versions
      current   = installed.last

      # not outdated unless there is a different version on tap
      return [] if current == version

      # collect all installed versions that are different than tap version and return them
      installed.reject { |v| v == version }
    end

    def outdated_info(greedy, verbose, json, greedy_latest, greedy_auto_updates)
      return token if !verbose && !json

      installed_versions = outdated_versions(greedy: greedy, greedy_latest: greedy_latest,
                                             greedy_auto_updates: greedy_auto_updates).join(", ")

      if json
        {
          name:               token,
          installed_versions: installed_versions,
          current_version:    version,
        }
      else
        "#{token} (#{installed_versions}) != #{version}"
      end
    end

    def to_s
      @token
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
        "token"          => token,
        "full_token"     => full_name,
        "tap"            => tap&.name,
        "name"           => name,
        "desc"           => desc,
        "homepage"       => homepage,
        "url"            => url,
        "appcast"        => appcast,
        "version"        => version,
        "installed"      => versions.last,
        "outdated"       => outdated?,
        "sha256"         => sha256,
        "artifacts"      => artifacts.map(&method(:to_h_gsubs)),
        "caveats"        => (to_h_string_gsubs(caveats) unless caveats.empty?),
        "depends_on"     => depends_on,
        "conflicts_with" => conflicts_with,
        "container"      => container,
        "auto_updates"   => auto_updates,
      }
    end

    private

    def to_h_string_gsubs(string)
      string.to_s
            .gsub(ENV["HOME"], "$HOME")
            .gsub(HOMEBREW_PREFIX, "$(brew --prefix)")
    end

    def to_h_array_gsubs(array)
      array.to_a.map do |value|
        to_h_gsubs(value)
      end
    end

    def to_h_hash_gsubs(hash)
      hash.to_h.transform_values do |value|
        to_h_gsubs(value)
      end
    rescue TypeError
      to_h_array_gsubs(hash)
    end

    def to_h_gsubs(value)
      if value.respond_to? :to_h
        to_h_hash_gsubs(value)
      elsif value.respond_to? :to_a
        to_h_array_gsubs(value)
      else
        to_h_string_gsubs(value)
      end
    end
  end
end
