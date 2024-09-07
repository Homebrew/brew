# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "extend/cachable"
require "api/download"

module Homebrew
  module API
    # Helper functions for using the cask JSON API.
    module Cask
      extend Cachable

      DEFAULT_API_FILENAME = "cask.jws.json"

      private_class_method :cache

      sig { params(token: String).returns(Hash) }
      def self.fetch(token)
        Homebrew::API.fetch "cask/#{token}.json"
      end

      sig { params(cask: ::Cask::Cask).returns(::Cask::Cask) }
      def self.source_download(cask)
        path = cask.ruby_source_path.to_s || "Casks/#{cask.token}.rb"
        sha256 = cask.ruby_source_checksum[:sha256]
        checksum = Checksum.new(sha256) if sha256
        git_head = cask.tap_git_head || "HEAD"
        tap = cask.tap&.full_name || "Homebrew/homebrew-cask"

        download = Homebrew::API::Download.new(
          "https://raw.githubusercontent.com/#{tap}/#{git_head}/#{path}",
          checksum,
          mirrors: [
            "#{HOMEBREW_API_DEFAULT_DOMAIN}/cask-source/#{File.basename(path)}",
          ],
          cache:   HOMEBREW_CACHE_API_SOURCE/"#{tap}/#{git_head}/Cask",
        )
        download.fetch
        ::Cask::CaskLoader::FromPathLoader.new(download.symlink_location)
                                          .load(config: cask.config)
      end

      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_casks, updated = Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME

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

      sig { returns(T::Hash[String, Hash]) }
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

      sig { params(regenerate: T::Boolean).void }
      def self.write_names(regenerate: false)
        download_and_cache_data! unless cache.key?("casks")

        Homebrew::API.write_names_file(all_casks.keys, "cask", regenerate:)
      end
    end
  end
end
