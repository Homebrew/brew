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
      extend T::Generic
      extend Cachable

      # Sorbet type members are mutable by design and cannot be frozen.
      # rubocop:disable Style/MutableConstant
      Cache = type_template { { fixed: T::Hash[String, T.untyped] } }
      # rubocop:enable Style/MutableConstant

      private_class_method :cache

      sig { returns(Utils::Bottles::Tag) }
      private_class_method def self.effective_tag
        @effective_tag ||= T.let(SimulateSystem.current_tag, T.nilable(Utils::Bottles::Tag))
      end

      sig { returns(Utils::Bottles::Tag) }
      private_class_method def self.fallback_tag
        effective_tag
      end

      sig { returns(String) }
      private_class_method def self.packages_endpoint
        "internal/packages.#{effective_tag}.jws.json"
      end

      sig { params(name: String).returns(Homebrew::API::FormulaStruct) }
      def self.formula_struct(name)
        return cache["formula_structs"][name] if cache.key?("formula_structs") && cache["formula_structs"].key?(name)

        hash = formula_hashes[name]
        raise "No formula found for #{name}" unless hash

        struct = Homebrew::API::FormulaStruct.deserialize(hash, bottle_tag: effective_tag)

        cache["formula_structs"] ||= {}
        cache["formula_structs"][name] = struct

        struct
      end

      sig { params(name: String).returns(Homebrew::API::CaskStruct) }
      def self.cask_struct(name)
        return cache["cask_structs"][name] if cache.key?("cask_structs") && cache["cask_structs"].key?(name)

        hash = cask_hashes[name]
        raise "No cask found for #{name}" unless hash

        struct = Homebrew::API::CaskStruct.deserialize(hash)

        cache["cask_structs"] ||= {}
        cache["cask_structs"][name] = struct

        struct
      end

      sig { returns(Pathname) }
      def self.cached_packages_json_file_path
        HOMEBREW_CACHE_API/packages_endpoint
      end

      sig {
        params(download_queue: Homebrew::DownloadQueue, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T::Hash[String, T.untyped], T::Boolean])
      }
      def self.fetch_packages_api!(download_queue: Homebrew.default_download_queue, stale_seconds: nil,
                                   enqueue: false)
        old_failed = Homebrew.failed?
        json_contents, updated = begin
          Homebrew::API.fetch_json_api_file(packages_endpoint, stale_seconds:, download_queue:, enqueue:)
        rescue ErrorDuringExecution => e
          raise if e.stderr.exclude?("HTTP status: 404") || effective_tag == fallback_tag

          @effective_tag = fallback_tag
          Homebrew.failed = old_failed
          retry
        end

        [T.cast(json_contents, T::Hash[String, T.untyped]), updated]
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_contents, updated = fetch_packages_api!
        cache["formula_structs"] = {}
        cache["cask_structs"] = {}
        cache["formula_aliases"] = json_contents["formula_aliases"]
        cache["formula_renames"] = json_contents["formula_renames"]
        cache["cask_renames"] = json_contents["cask_renames"]
        cache["formula_tap_git_head"] = json_contents["formula_tap_git_head"]
        cache["cask_tap_git_head"] = json_contents["cask_tap_git_head"]
        cache["formula_tap_migrations"] = json_contents["formula_tap_migrations"]
        cache["cask_tap_migrations"] = json_contents["cask_tap_migrations"]
        cache["formula_hashes"] = json_contents["formulae"]
        cache["cask_hashes"] = json_contents["casks"]

        updated
      end
      private_class_method :download_and_cache_data!

      sig { params(regenerate: T::Boolean).void }
      def self.write_formula_names_and_aliases(regenerate: false)
        download_and_cache_data! unless cache.key?("formula_hashes")

        Homebrew::API.write_names_file!(formula_hashes.keys, "formula", regenerate:)
        Homebrew::API.write_aliases_file!(formula_aliases, "formula", regenerate:)
        Homebrew::API.write_executables_file!(formula_hashes, regenerate:)
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_cask_names(regenerate: false)
        download_and_cache_data! unless cache.key?("cask_hashes")

        Homebrew::API.write_names_file!(cask_hashes.keys, "cask", regenerate:)
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.formula_hashes
        unless cache.key?("formula_hashes")
          updated = download_and_cache_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_hashes"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_aliases
        unless cache.key?("formula_aliases")
          updated = download_and_cache_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_aliases"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_renames
        unless cache.key?("formula_renames")
          updated = download_and_cache_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_renames"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_tap_migrations
        unless cache.key?("formula_tap_migrations")
          updated = download_and_cache_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_tap_migrations"]
      end

      sig { returns(String) }
      def self.formula_tap_git_head
        unless cache.key?("formula_tap_git_head")
          updated = download_and_cache_data!
          write_formula_names_and_aliases(regenerate: updated)
        end

        cache["formula_tap_git_head"]
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.cask_hashes
        unless cache.key?("cask_hashes")
          updated = download_and_cache_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_hashes"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_renames
        unless cache.key?("cask_renames")
          updated = download_and_cache_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_renames"]
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_tap_migrations
        unless cache.key?("cask_tap_migrations")
          updated = download_and_cache_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_tap_migrations"]
      end

      sig { returns(String) }
      def self.cask_tap_git_head
        unless cache.key?("cask_tap_git_head")
          updated = download_and_cache_data!
          write_cask_names(regenerate: updated)
        end

        cache["cask_tap_git_head"]
      end
    end
  end
end

require "extend/os/api/internal"
