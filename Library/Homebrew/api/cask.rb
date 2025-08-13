# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "download_queue"

module Homebrew
  module API
    # Helper functions for using the cask JSON API.
    module Cask
      extend Cachable

      DEFAULT_API_FILENAME = "cask.jws.json"

      private_class_method :cache

      sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      def self.cask_json(name)
        fetch_cask_json! name if !cache.key?("cask_json") || !cache.fetch("cask_json").key?(name)

        cache.fetch("cask_json").fetch(name)
      end

      sig { params(name: String, download_queue: T.nilable(DownloadQueue)).void }
      def self.fetch_cask_json!(name, download_queue: nil)
        endpoint = "cask/#{name}.json"
        json_cask, updated = Homebrew::API.fetch_json_api_file endpoint, download_queue: download_queue
        return if download_queue

        json_cask = JSON.parse((HOMEBREW_CACHE_API/endpoint).read) unless updated

        cache["cask_json"] ||= {}
        cache["cask_json"][name] = json_cask
      end

      sig { params(cask: ::Cask::Cask, download_queue: T.nilable(Homebrew::DownloadQueue)).returns(Homebrew::API::SourceDownload) }
      def self.source_download(cask, download_queue: nil)
        path = cask.ruby_source_path.to_s
        sha256 = cask.ruby_source_checksum[:sha256]
        checksum = Checksum.new(sha256) if sha256
        git_head = cask.tap_git_head || "HEAD"
        tap = cask.tap&.full_name || "Homebrew/homebrew-cask"

        download = Homebrew::API::SourceDownload.new(
          "https://raw.githubusercontent.com/#{tap}/#{git_head}/#{path}",
          checksum,
          mirrors: [
            "#{HOMEBREW_API_DEFAULT_DOMAIN}/cask-source/#{File.basename(path)}",
          ],
          cache:   HOMEBREW_CACHE_API_SOURCE/"#{tap}/#{git_head}/Cask",
        )

        if download_queue
          download_queue.enqueue(download)
        elsif !download.symlink_location.exist?
          download.fetch
        end

        download
      end

      sig { params(cask: ::Cask::Cask).returns(::Cask::Cask) }
      def self.source_download_cask(cask)
        download = source_download(cask)

        ::Cask::CaskLoader::FromPathLoader.new(download.symlink_location)
                                          .load(config: cask.config)
      end

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig {
        params(download_queue: T.nilable(::Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_api!(download_queue: nil, stale_seconds: Homebrew::EnvConfig.api_auto_update_secs.to_i)
        Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME, stale_seconds:, download_queue:
      end

      sig {
        params(download_queue: T.nilable(::Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_tap_migrations!(download_queue: nil, stale_seconds: Homebrew::API::TAP_MIGRATIONS_STALE_SECONDS)
        Homebrew::API.fetch_json_api_file "cask_tap_migrations.jws.json", stale_seconds:, download_queue:
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_casks, updated = fetch_api!

        cache["renames"] = {}
        cache["casks"] = json_casks.to_h do |json_cask|
          token = json_cask["token"]

          json_cask.fetch("old_tokens", []).each do |old_token|
            cache["renames"][old_token] = token
          end

          [token, json_cask.except("token")]
        end

        updated
      end
      private_class_method :download_and_cache_data!

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.all_casks
        unless cache.key?("casks")
          json_updated = download_and_cache_data!
          write_names(regenerate: json_updated)
        end

        cache.fetch("casks")
      end

      sig { returns(T::Hash[String, String]) }
      def self.all_renames
        unless cache.key?("renames")
          json_updated = download_and_cache_data!
          write_names(regenerate: json_updated)
        end

        cache.fetch("renames")
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def self.tap_migrations
        unless cache.key?("tap_migrations")
          json_migrations, = fetch_tap_migrations!
          cache["tap_migrations"] = json_migrations
        end

        cache.fetch("tap_migrations")
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_names(regenerate: false)
        download_and_cache_data! unless cache.key?("casks")

        Homebrew::API.write_names_file!(all_casks.keys, "cask", regenerate:)
      end
    end
  end
end
