# frozen_string_literal: true

require_relative "base"
require_relative "../worker"

module Bundler
  autoload :CompactIndexClient, File.expand_path("../compact_index_client", __dir__)

  class Fetcher
    class CompactIndex < Base
      def self.compact_index_request(method_name)
        method = instance_method(method_name)
        undef_method(method_name)
        define_method(method_name) do |*args, &blk|
          begin
            method.bind(self).call(*args, &blk)
          rescue NetworkDownError, CompactIndexClient::Updater::MisMatchedChecksumError => e
            raise HTTPError, e.message
          rescue AuthenticationRequiredError
            # Fail since we got a 401 from the server.
            raise
          rescue HTTPError => e
            Bundler.ui.trace(e)
            nil
          end
        end
      end

      def specs(gem_names)
        specs_for_names(gem_names)
      end
      compact_index_request :specs

      def specs_for_names(gem_names)
        gem_info = []
        complete_gems = []
        remaining_gems = gem_names.dup

        until remaining_gems.empty?
          log_specs "Looking up gems #{remaining_gems.inspect}"

          deps = begin
                   parallel_compact_index_client.dependencies(remaining_gems)
                 rescue TooManyRequestsError
                   @bundle_worker.stop if @bundle_worker
                   @bundle_worker = nil # reset it.  Not sure if necessary
                   serial_compact_index_client.dependencies(remaining_gems)
                 end
          next_gems = deps.map {|d| d[3].map(&:first).flatten(1) }.flatten(1).uniq
          deps.each {|dep| gem_info << dep }
          complete_gems.concat(deps.map(&:first)).uniq!
          remaining_gems = next_gems - complete_gems
        end
        @bundle_worker.stop if @bundle_worker
        @bundle_worker = nil # reset it.  Not sure if necessary

        gem_info
      end

      def available?
        unless SharedHelpers.md5_available?
          Bundler.ui.debug("FIPS mode is enabled, bundler can't use the CompactIndex API")
          return nil
        end
        if fetch_uri.scheme == "file"
          Bundler.ui.debug("Using a local server, bundler won't use the CompactIndex API")
          return false
        end
        # Read info file checksums out of /versions, so we can know if gems are up to date
        compact_index_client.update_and_parse_checksums!
      rescue CompactIndexClient::Updater::MisMatchedChecksumError => e
        Bundler.ui.debug(e.message)
        nil
      end
      compact_index_request :available?

      def api_fetcher?
        true
      end

      private

      def compact_index_client
        @compact_index_client ||=
          SharedHelpers.filesystem_access(cache_path) do
            CompactIndexClient.new(cache_path, client_fetcher)
          end
      end

      def parallel_compact_index_client
        compact_index_client.execution_mode = lambda do |inputs, &blk|
          func = lambda {|object, _index| blk.call(object) }
          worker = bundle_worker(func)
          inputs.each {|input| worker.enq(input) }
          inputs.map { worker.deq }
        end

        compact_index_client
      end

      def serial_compact_index_client
        compact_index_client.sequential_execution_mode!
        compact_index_client
      end

      def bundle_worker(func = nil)
        @bundle_worker ||= begin
          worker_name = "Compact Index (#{display_uri.host})"
          Bundler::Worker.new(Bundler.settings.processor_count, worker_name, func)
        end
        @bundle_worker.tap do |worker|
          worker.instance_variable_set(:@func, func) if func
        end
      end

      def cache_path
        Bundler.user_cache.join("compact_index", remote.cache_slug)
      end

      def client_fetcher
        ClientFetcher.new(self, Bundler.ui)
      end

      ClientFetcher = Struct.new(:fetcher, :ui) do
        def call(path, headers)
          fetcher.downloader.fetch(fetcher.fetch_uri + path, headers)
        rescue NetworkDownError => e
          raise unless Bundler.feature_flag.allow_offline_install? && headers["If-None-Match"]
          ui.warn "Using the cached data for the new index because of a network error: #{e}"
          Net::HTTPNotModified.new(nil, nil, nil)
        end
      end
    end
  end
end
