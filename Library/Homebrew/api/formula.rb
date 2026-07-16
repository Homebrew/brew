# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "local_patch"
require "download_queue"
require "api/formula/formula_struct_generator"

module Homebrew
  module API
    # Helper functions for using the formula JSON API.
    module Formula
      extend T::Generic
      extend Cachable

      Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

      DEFAULT_API_FILENAME = "formula.jws.json"

      private_class_method :cache

      sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      def self.formula_json(name)
        fetch_formula_json! name if !cache.key?("formula_json") || !cache.fetch("formula_json").key?(name)

        cache.fetch("formula_json").fetch(name)
      end

      sig { params(name: String).void }
      def self.fetch_formula_json!(name)
        endpoint = "formula/#{name}.json"
        json_formula, updated = Homebrew::API.fetch_json_api_file endpoint

        json_formula = JSON.parse((HOMEBREW_CACHE_API/endpoint).read) unless updated

        cache["formula_json"] ||= {}
        cache["formula_json"][name] = json_formula
      end

      sig {
        params(
          formula:        ::Formula,
          path:           String,
          checksum:       T.nilable(Checksum),
          download_queue: Homebrew::DownloadQueue,
          enqueue:        T::Boolean,
        ).returns(Homebrew::API::SourceDownload)
      }
      def self.source_download_path(formula, path, checksum: nil, download_queue: Homebrew.default_download_queue,
                                    enqueue: false)
        unless LocalPatch.valid_path?(path)
          raise ArgumentError, "API source path must be a relative path within the repository."
        end

        path = Pathname(path).cleanpath

        git_head = formula.tap_git_head || "HEAD"
        tap = formula.tap&.full_name || "Homebrew/homebrew-core"

        download = Homebrew::API::SourceDownload.new(
          "https://raw.githubusercontent.com/#{tap}/#{git_head}/#{path}",
          checksum,
          cache: HOMEBREW_CACHE_API_SOURCE/"#{tap}/#{git_head}"/path.dirname,
        )

        if enqueue
          download_queue.enqueue(download)
        elsif !download.symlink_location.exist? || !download.symlink_location.symlink?
          download.fetch
        end

        download
      end

      sig {
        params(
          formula:        ::Formula,
          download_queue: Homebrew::DownloadQueue,
          enqueue:        T::Boolean,
        ).returns(Homebrew::API::SourceDownload)
      }
      def self.source_download(formula, download_queue: Homebrew.default_download_queue, enqueue: false)
        path = formula.ruby_source_path || "Formula/#{formula.name}.rb"
        source_download_path(formula, path, checksum: formula.ruby_source_checksum, download_queue:, enqueue:)
      end

      sig { params(formula: ::Formula).returns(::Formula) }
      def self.source_download_formula(formula)
        download = source_download(formula)

        unless download.symlink_location.exist?
          raise CannotInstallFormulaError,
                "#{formula.full_name} source code not found at #{download.symlink_location}. " \
                "Try `rm -rf $(brew --cache)/api-source` and retrying."
        end

        source_formula = with_env(HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS: "1") do
          Formulary.factory(download.symlink_location,
                            formula.active_spec_sym,
                            alias_path: formula.alias_path,
                            flags:      formula.class.build_flags)
        end

        source_formula.resources.each do |resource|
          resource.patches.grep(LocalPatch) do |patch|
            source_download_path(formula, patch.file.to_s)
          end
        end
        source_formula.patchlist.grep(LocalPatch) do |patch|
          source_download_path(formula, patch.file.to_s)
        end

        source_formula
      end

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig {
        params(download_queue: Homebrew::DownloadQueue, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_api!(download_queue: Homebrew.default_download_queue, stale_seconds: nil, enqueue: false)
        Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME, stale_seconds:, download_queue:, enqueue:
      end

      sig {
        params(download_queue: Homebrew::DownloadQueue, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_tap_migrations!(download_queue: Homebrew.default_download_queue, stale_seconds: nil,
                                     enqueue: false)
        Homebrew::API.fetch_json_api_file "formula_tap_migrations.jws.json", stale_seconds:, download_queue:, enqueue:
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

        Homebrew::API.write_names_file!(all_formulae.keys, "formula", regenerate:)
        Homebrew::API.write_aliases_file!(all_aliases, "formula", regenerate:)
        Homebrew::API.write_executables_file!(all_formulae, regenerate:)
      end
    end
  end
end
