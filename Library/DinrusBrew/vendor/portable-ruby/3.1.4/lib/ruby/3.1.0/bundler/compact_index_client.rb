# frozen_string_literal: true

require "pathname"
require "set"

module Bundler
  class CompactIndexClient
    DEBUG_MUTEX = Thread::Mutex.new
    def self.debug
      return unless ENV["DEBUG_COMPACT_INDEX"]
      DEBUG_MUTEX.synchronize { warn("[#{self}] #{yield}") }
    end

    class Error < StandardError; end

    require_relative "compact_index_client/cache"
    require_relative "compact_index_client/updater"

    attr_reader :directory

    def initialize(directory, fetcher)
      @directory = Pathname.new(directory)
      @updater = Updater.new(fetcher)
      @cache = Cache.new(@directory)
      @endpoints = Set.new
      @info_checksums_by_name = {}
      @parsed_checksums = false
      @mutex = Thread::Mutex.new
    end

    def execution_mode=(block)
      Bundler::CompactIndexClient.debug { "execution_mode=" }
      @endpoints = Set.new

      @execution_mode = block
    end

    # @return [Lambda] A lambda that takes an array of inputs and a block, and
    #         maps the inputs with the block in parallel.
    #
    def execution_mode
      @execution_mode || sequentially
    end

    def sequential_execution_mode!
      self.execution_mode = sequentially
    end

    def sequentially
      @sequentially ||= lambda do |inputs, &blk|
        inputs.map(&blk)
      end
    end

    def names
      Bundler::CompactIndexClient.debug { "/names" }
      update(@cache.names_path, "names")
      @cache.names
    end

    def versions
      Bundler::CompactIndexClient.debug { "/versions" }
      update(@cache.versions_path, "versions")
      versions, @info_checksums_by_name = @cache.versions
      versions
    end

    def dependencies(names)
      Bundler::CompactIndexClient.debug { "dependencies(#{names})" }
      execution_mode.call(names) do |name|
        update_info(name)
        @cache.dependencies(name).map {|d| d.unshift(name) }
      end.flatten(1)
    end

    def update_and_parse_checksums!
      Bundler::CompactIndexClient.debug { "update_and_parse_checksums!" }
      return @info_checksums_by_name if @parsed_checksums
      update(@cache.versions_path, "versions")
      @info_checksums_by_name = @cache.checksums
      @parsed_checksums = true
    end

    private

    def update(local_path, remote_path)
      Bundler::CompactIndexClient.debug { "update(#{local_path}, #{remote_path})" }
      unless synchronize { @endpoints.add?(remote_path) }
        Bundler::CompactIndexClient.debug { "already fetched #{remote_path}" }
        return
      end
      @updater.update(local_path, url(remote_path))
    end

    def update_info(name)
      Bundler::CompactIndexClient.debug { "update_info(#{name})" }
      path = @cache.info_path(name)
      checksum = @updater.checksum_for_file(path)
      unless existing = @info_checksums_by_name[name]
        Bundler::CompactIndexClient.debug { "skipping updating info for #{name} since it is missing from versions" }
        return
      end
      if checksum == existing
        Bundler::CompactIndexClient.debug { "skipping updating info for #{name} since the versions checksum matches the local checksum" }
        return
      end
      Bundler::CompactIndexClient.debug { "updating info for #{name} since the versions checksum #{existing} != the local checksum #{checksum}" }
      update(path, "info/#{name}")
    end

    def url(path)
      path
    end

    def synchronize
      @mutex.synchronize { yield }
    end
  end
end
