# frozen_string_literal: true

require "pathname"
require "set"

module Bundler
  # The CompactIndexClient is responsible for fetching and parsing the compact index.
  #
  # The compact index is a set of caching optimized files that are used to fetch gem information.
  # The files are:
  # - names: a list of all gem names
  # - versions: a list of all gem versions
  # - info/[gem]: a list of all versions of a gem
  #
  # The client is instantiated with:
  # - `directory`: the root directory where the cache files are stored.
  # - `fetcher`: (optional) an object that responds to #call(uri_path, headers) and returns an http response.
  # If the `fetcher` is not provided, the client will only read cached files from disk.
  #
  # The client is organized into:
  # - `Updater`: updates the cached files on disk using the fetcher.
  # - `Cache`: calls the updater, caches files, read and return them from disk
  # - `Parser`: parses the compact index file data
  # - `CacheFile`: a concurrency safe file reader/writer that verifies checksums
  #
  # The client is intended to optimize memory usage and performance.
  # It is called 100s or 1000s of times, parsing files with hundreds of thousands of lines.
  # It may be called concurrently without global interpreter lock in some Rubies.
  # As a result, some methods may look more complex than necessary to save memory or time.
  class CompactIndexClient
    # NOTE: MD5 is here not because we expect a server to respond with it, but
    # because we use it to generate the etag on first request during the upgrade
    # to the compact index client that uses opaque etags saved to files.
    # Remove once 2.5.0 has been out for a while.
    SUPPORTED_DIGESTS = { "sha-256" => :SHA256, "md5" => :MD5 }.freeze
    DEBUG_MUTEX = Thread::Mutex.new

    # info returns an Array of INFO Arrays. Each INFO Array has the following indices:
    INFO_NAME = 0
    INFO_VERSION = 1
    INFO_PLATFORM = 2
    INFO_DEPS = 3
    INFO_REQS = 4

    def self.debug
      return unless ENV["DEBUG_COMPACT_INDEX"]
      DEBUG_MUTEX.synchronize { warn("[#{self}] #{yield}") }
    end

    class Error < StandardError; end

    require_relative "compact_index_client/cache"
    require_relative "compact_index_client/cache_file"
    require_relative "compact_index_client/parser"
    require_relative "compact_index_client/updater"

    def initialize(directory, fetcher = nil)
      @cache = Cache.new(directory, fetcher)
      @parser = Parser.new(@cache)
    end

    def names
      Bundler::CompactIndexClient.debug { "names" }
      @parser.names
    end

    def versions
      Bundler::CompactIndexClient.debug { "versions" }
      @parser.versions
    end

    def dependencies(names)
      Bundler::CompactIndexClient.debug { "dependencies(#{names})" }
      names.map {|name| info(name) }
    end

    def info(name)
      Bundler::CompactIndexClient.debug { "info(#{name})" }
      @parser.info(name)
    end

    def latest_version(name)
      Bundler::CompactIndexClient.debug { "latest_version(#{name})" }
      @parser.info(name).map {|d| Gem::Version.new(d[INFO_VERSION]) }.max
    end

    def available?
      Bundler::CompactIndexClient.debug { "available?" }
      @parser.available?
    end

    def reset!
      Bundler::CompactIndexClient.debug { "reset!" }
      @cache.reset!
    end
  end
end
