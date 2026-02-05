# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "download_queue"

module Homebrew
  module API
    # Helper functions for using the JSON internal API.
    module Internal
      extend Cachable

      private_class_method :cache

      sig { returns(String) }
      def self.formula_endpoint
        "internal/formula.#{SimulateSystem.current_tag}.jws.json"
      end

      sig { returns(String) }
      def self.cask_endpoint
        "internal/cask.#{SimulateSystem.current_tag}.jws.json"
      end

      sig { params(name: String).returns(Homebrew::API::FormulaStruct) }
      def self.formula_struct(name)
        return cache["formula_structs"][name] if cache.key?("formula_structs") && cache["formula_structs"].key?(name)

        hash = formula_hashes[name]
        raise "No formula found for #{name}" unless hash

        struct = Homebrew::API::FormulaStruct.deserialize(hash, bottle_tag: SimulateSystem.current_tag)

        cache["formula_structs"] ||= {}
        cache["formula_structs"][name] = struct

        struct
      end

      sig { returns(Pathname) }
      def self.cached_formula_json_file_path
        HOMEBREW_CACHE_API/formula_endpoint
      end

      sig { returns(Pathname) }
      def self.cached_cask_json_file_path
        HOMEBREW_CACHE_API/cask_endpoint
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: T.nilable(Integer))
          .returns([T::Hash[String, T.untyped], T::Boolean])
      }
      def self.fetch_formula_api!(download_queue: nil, stale_seconds: nil)
        json_contents, updated = Homebrew::API.fetch_json_api_file(formula_endpoint, stale_seconds:, download_queue:)
        [T.cast(json_contents, T::Hash[String, T.untyped]), updated]
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: T.nilable(Integer))
          .returns([T::Hash[String, T.untyped], T::Boolean])
      }
      def self.fetch_cask_api!(download_queue: nil, stale_seconds: nil)
        json_contents, updated = Homebrew::API.fetch_json_api_file(cask_endpoint, stale_seconds:, download_queue:)
        [T.cast(json_contents, T::Hash[String, T.untyped]), updated]
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_formula_data!
        json_contents, updated = fetch_formula_api!
        cache["formula_structs"] = {}
        cache["formula_aliases"] = json_contents["aliases"]
        cache["formula_renames"] = json_contents["renames"]
        cache["formula_tap_git_head"] = json_contents["tap_git_head"]
        cache["formula_tap_migrations"] = json_contents["tap_migrations"]
        cache["formula_hashes"] = json_contents["formulae"]

        updated
      end
      private_class_method :download_and_cache_formula_data!

      sig { returns(T::Boolean) }
      def self.download_and_cache_cask_data!
        json_contents, updated = fetch_cask_api!
        cache["cask_stubs"] = {}
        cache["cask_renames"] = json_contents["renames"]
        cache["cask_tap_migrations"] = json_contents["tap_migrations"]
        cache["cask_hashes"] = json_contents["casks"]

        updated
      end
      private_class_method :download_and_cache_cask_data!

      sig { params(regenerate: T::Boolean).void }
      def self.write_formula_names_and_aliases(regenerate: false)
        download_and_cache_formula_data! unless cache.key?("formula_hashes")

        Homebrew::API.write_names_file!(formula_hashes.keys, "formula", regenerate:)
        Homebrew::API.write_aliases_file!(formula_aliases, "formula", regenerate:)
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_cask_names(regenerate: false)
        download_and_cache_cask_data! unless cache.key?("cask_hashes")

        Homebrew::API.write_names_file!(cask_hashes.keys, "cask", regenerate:)
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.formula_hashes
        unless cache.key?("formula_hashes")
          updated = download_and_cache_formula_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_hashes"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_aliases
        unless cache.key?("formula_aliases")
          updated = download_and_cache_formula_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_aliases"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_renames
        unless cache.key?("formula_renames")
          updated = download_and_cache_formula_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_renames"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_tap_migrations
        unless cache.key?("formula_tap_migrations")
          updated = download_and_cache_formula_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_tap_migrations"]
      end

      sig { returns(String) }
      def self.formula_tap_git_head
        unless cache.key?("formula_tap_git_head")
          updated = download_and_cache_formula_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_tap_git_head"]
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.cask_hashes
        unless cache.key?("cask_hashes")
          updated = download_and_cache_cask_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_hashes"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_renames
        unless cache.key?("cask_renames")
          updated = download_and_cache_cask_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_renames"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_tap_migrations
        unless cache.key?("cask_tap_migrations")
          updated = download_and_cache_cask_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_tap_migrations"]
      end
    end
  end
end
