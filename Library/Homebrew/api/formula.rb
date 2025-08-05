# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "download_queue"

module Homebrew
  module API
    # Helper functions for using the formula JSON API.
    module Formula
      extend Cachable

      DEFAULT_API_FILENAME = "formula.jws.json"

      private_class_method :cache

      sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      def self.fetch(name)
        Homebrew::API.fetch "formula/#{name}.json"
      end

      sig { params(formula: ::Formula, download_queue: T.nilable(Homebrew::DownloadQueue)).returns(Homebrew::API::SourceDownload) }
      def self.source_download(formula, download_queue: nil)
        path = formula.ruby_source_path || "Formula/#{formula.name}.rb"
        git_head = formula.tap_git_head || "HEAD"
        tap = formula.tap&.full_name || "Homebrew/homebrew-core"

        download = Homebrew::API::SourceDownload.new(
          "https://raw.githubusercontent.com/#{tap}/#{git_head}/#{path}",
          formula.ruby_source_checksum,
          cache: HOMEBREW_CACHE_API_SOURCE/"#{tap}/#{git_head}/Formula",
        )

        if download_queue
          download_queue.enqueue(download)
        elsif !download.symlink_location.exist?
          download.fetch
        end

        download
      end

      sig { params(formula: ::Formula).returns(::Formula) }
      def self.source_download_formula(formula)
        download = source_download(formula)

        with_env(HOMEBREW_FORBID_PACKAGES_FROM_PATHS: nil) do
          Formulary.factory(download.symlink_location,
                            formula.active_spec_sym,
                            alias_path: formula.alias_path,
                            flags:      formula.class.build_flags)
        end
      end

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_api!(download_queue: nil, stale_seconds: Homebrew::EnvConfig.api_auto_update_secs.to_i)
        Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME, stale_seconds:, download_queue:
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_tap_migrations!(download_queue: nil, stale_seconds: Homebrew::API::TAP_MIGRATIONS_STALE_SECONDS)
        Homebrew::API.fetch_json_api_file "formula_tap_migrations.jws.json", stale_seconds:, download_queue:
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_formulae, updated = fetch_api!

        cache["aliases"] = {}
        cache["renames"] = {}
        cache["formulae"] = json_formulae.to_h do |json_formula|
          json_formula["aliases"].each do |alias_name|
            cache["aliases"][alias_name] = json_formula["name"]
          end
          (json_formula["oldnames"] || [json_formula["oldname"]].compact).each do |oldname|
            cache["renames"][oldname] = json_formula["name"]
          end

          [json_formula["name"], json_formula.except("name")]
        end

        updated
      end
      private_class_method :download_and_cache_data!

      sig { returns(T::Hash[String, T.untyped]) }
      def self.all_formulae
        unless cache.key?("formulae")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
        end

        cache.fetch("formulae")
      end

      sig { returns(T::Hash[String, String]) }
      def self.all_aliases
        unless cache.key?("aliases")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
        end

        cache.fetch("aliases")
      end

      sig { returns(T::Hash[String, String]) }
      def self.all_renames
        unless cache.key?("renames")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
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
      def self.write_names_and_aliases(regenerate: false)
        download_and_cache_data! unless cache.key?("formulae")

        return unless Homebrew::API.write_names_file!(all_formulae.keys, "formula", regenerate:)

        (HOMEBREW_CACHE_API/"formula_aliases.txt").open("w") do |file|
          all_aliases.each do |alias_name, real_name|
            file.puts "#{alias_name}|#{real_name}"
          end
        end
      end
    end
  end
end
