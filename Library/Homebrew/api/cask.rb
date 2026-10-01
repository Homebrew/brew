# typed: strict
# frozen_string_literal: true

require "cacheable"
require "api"
require "api/cask/cask_struct_generator"

module Homebrew
  module API
    # Helper functions for using the cask JSON API.
    module Cask
      extend T::Generic
      extend Cacheable

      Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

      DEFAULT_API_FILENAME = "cask.jws.json"

      private_class_method :cache

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig {
        params(download_queue: DownloadQueueType, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_api!(download_queue: nil, stale_seconds: nil, enqueue: false)
        Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME, stale_seconds:, download_queue:, enqueue:
      end

      sig {
        params(download_queue: DownloadQueueType, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_tap_migrations!(download_queue: nil, stale_seconds: nil, enqueue: false)
        Homebrew::API.fetch_json_api_file "cask_tap_migrations.jws.json", stale_seconds:, download_queue:, enqueue:
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

        Homebrew::API.write_names_file!("cask", regenerate:) { all_casks.keys }
      end
    end
  end
end
