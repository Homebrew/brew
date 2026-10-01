# typed: strict
# frozen_string_literal: true

require "cacheable"
require "api"
require "api/packages_index"

module Homebrew
  module API
    # Helper functions for using the JSON internal API.
    module Internal
      extend T::Generic
      extend Cacheable

      Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

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

        hash = formula_hash(name)
        raise "No formula found for #{name}" unless hash

        struct = Homebrew::API::FormulaStruct.deserialize(hash, bottle_tag: effective_tag)

        cache["formula_structs"] ||= {}
        cache["formula_structs"][name] = struct

        struct
      end

      sig { params(name: String).returns(Homebrew::API::CaskStruct) }
      def self.cask_struct(name)
        return cache["cask_structs"][name] if cache.key?("cask_structs") && cache["cask_structs"].key?(name)

        hash = cask_hash(name)
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
        params(download_queue: DownloadQueueType, stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns([T.any(T::Hash[String, T.untyped], Homebrew::API::PackagesIndex), T::Boolean])
      }
      def self.fetch_packages_api!(download_queue: nil, stale_seconds: nil, enqueue: false)
        old_failed = Homebrew.failed?
        json_contents, updated = begin
          cached_packages_index(stale_seconds:, enqueue:) ||
            Homebrew::API.fetch_json_api_file(packages_endpoint, stale_seconds:, download_queue:, enqueue:)
        rescue ErrorDuringExecution => e
          raise if e.stderr.exclude?("HTTP status: 404") || effective_tag == fallback_tag

          @effective_tag = fallback_tag
          Homebrew.failed = old_failed
          retry
        end

        [T.cast(json_contents, T.any(T::Hash[String, T.untyped], Homebrew::API::PackagesIndex)), updated]
      end

      # Serves a fresh cached packages payload through its byte-offset index
      # so only the entries that get used are parsed, building the index
      # after a full parse when it is missing or stale.
      sig {
        params(stale_seconds: T.nilable(Integer), enqueue: T::Boolean)
          .returns(T.nilable([T.any(T::Hash[String, T.untyped], Homebrew::API::PackagesIndex), T::Boolean]))
      }
      private_class_method def self.cached_packages_index(stale_seconds:, enqueue:)
        return if enqueue

        cached = Homebrew::API.cached_internal_packages_payload(packages_endpoint, stale_seconds:)
        return if cached.nil?

        payload, source_stat = cached
        target = cached_packages_json_file_path
        index = Homebrew::API::PackagesIndex.load(target, payload:, source_stat:)
        return [index, false] if index

        parsed = JSON.parse(payload, freeze: true)
        return unless parsed.is_a?(Hash)

        Homebrew::API::PackagesIndex.write!(target, payload:, parsed:, source_stat:)
        [parsed, false]
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_contents, updated = fetch_packages_api!
        cache["formula_structs"] = {}
        cache["cask_structs"] = {}
        if json_contents.is_a?(Homebrew::API::PackagesIndex)
          cache["packages_index"] = json_contents
        else
          cache_parsed_packages!(json_contents)
        end

        updated
      end
      private_class_method :download_and_cache_data!

      sig { params(json_contents: T::Hash[String, T.untyped]).void }
      private_class_method def self.cache_parsed_packages!(json_contents)
        cache.delete("packages_index")
        cache["formula_aliases"] = json_contents["formula_aliases"]
        cache["formula_renames"] = json_contents["formula_renames"]
        cache["cask_renames"] = json_contents["cask_renames"]
        cache["formula_tap_git_head"] = json_contents["formula_tap_git_head"]
        cache["cask_tap_git_head"] = json_contents["cask_tap_git_head"]
        cache["formula_tap_migrations"] = json_contents["formula_tap_migrations"]
        cache["cask_tap_migrations"] = json_contents["cask_tap_migrations"]
        cache["formula_hashes"] = json_contents["formulae"]
        cache["cask_hashes"] = json_contents["casks"]
      end

      # Replaces a cached index with fully parsed payload data, for callers
      # that need every entry or when index validation fails.
      sig { void }
      private_class_method def self.materialize_packages_index!
        index = cache.delete("packages_index")
        return unless index.is_a?(Homebrew::API::PackagesIndex)

        parsed = JSON.parse(index.payload, freeze: true)
        return unless parsed.is_a?(Hash)

        cache_parsed_packages!(parsed)
        Homebrew::API::PackagesIndex.write!(cached_packages_json_file_path, payload: index.payload, parsed:,
                                            source_stat: index.source_stat)
      end

      sig { returns(T::Boolean) }
      private_class_method def self.data_loaded?
        cache.key?("formula_hashes") || cache.key?("packages_index")
      end

      sig { void }
      private_class_method def self.ensure_formula_data!
        return if data_loaded?

        updated = download_and_cache_data!
        write_formula_names_and_aliases(regenerate: updated)
      end

      sig { void }
      private_class_method def self.ensure_cask_data!
        return if data_loaded?

        updated = download_and_cache_data!
        write_cask_names(regenerate: updated)
      end

      sig { params(key: String).returns(T.untyped) }
      private_class_method def self.packages_value(key)
        return cache[key] if cache.key?(key)

        cache[key] = cache["packages_index"].top_level_value(key)
      rescue Homebrew::API::PackagesIndex::Invalid
        materialize_packages_index!
        cache[key]
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_formula_names_and_aliases(regenerate: false)
        download_and_cache_data! unless data_loaded?

        Homebrew::API.write_names_file!("formula", regenerate:) { formula_names }
        # Renames resolve like aliases in lightweight formula lookups.
        Homebrew::API.write_aliases_file!("formula", regenerate:) { formula_aliases.merge(formula_renames) }
        Homebrew::API.write_executables_file!(regenerate:, source: cached_packages_json_file_path) { formula_hashes }
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_cask_names(regenerate: false)
        download_and_cache_data! unless data_loaded?

        Homebrew::API.write_names_file!("cask", regenerate:) { cask_names }
      end

      # Whether internal packages API data is already loaded, as full hashes
      # or a byte-offset index, so callers can use it opportunistically
      # without triggering a download and full JSON parse.
      sig { returns(T::Boolean) }
      def self.formula_hashes_cached?
        data_loaded?
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.formula_hashes
        ensure_formula_data!
        materialize_packages_index! unless cache.key?("formula_hashes")

        cache["formula_hashes"]
      end

      sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def self.formula_hash(name)
        ensure_formula_data!
        return cache["formula_hashes"][name] if cache.key?("formula_hashes")

        begin
          cache["packages_index"].formula_hash(name)
        rescue Homebrew::API::PackagesIndex::Invalid
          materialize_packages_index!
          cache["formula_hashes"][name]
        end
      end

      sig { returns(T::Array[String]) }
      def self.formula_names
        ensure_formula_data!
        return cache["formula_hashes"].keys if cache.key?("formula_hashes")

        cache["packages_index"].formula_names
      end

      sig { params(name: String).returns(T::Boolean) }
      def self.formula_name?(name)
        ensure_formula_data!
        return cache["formula_hashes"].key?(name) if cache.key?("formula_hashes")

        cache["packages_index"].formula_name?(name)
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_aliases
        ensure_formula_data!
        packages_value("formula_aliases")
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_renames
        ensure_formula_data!
        packages_value("formula_renames")
      end

      sig { returns(T::Hash[String, String]) }
      def self.formula_tap_migrations
        ensure_formula_data!
        packages_value("formula_tap_migrations")
      end

      sig { returns(String) }
      def self.formula_tap_git_head
        ensure_formula_data!
        packages_value("formula_tap_git_head")
      end

      sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
      def self.cask_hashes
        ensure_cask_data!
        materialize_packages_index! unless cache.key?("cask_hashes")

        cache["cask_hashes"]
      end

      sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def self.cask_hash(name)
        ensure_cask_data!
        return cache["cask_hashes"][name] if cache.key?("cask_hashes")

        begin
          cache["packages_index"].cask_hash(name)
        rescue Homebrew::API::PackagesIndex::Invalid
          materialize_packages_index!
          cache["cask_hashes"][name]
        end
      end

      sig { returns(T::Array[String]) }
      def self.cask_names
        ensure_cask_data!
        return cache["cask_hashes"].keys if cache.key?("cask_hashes")

        cache["packages_index"].cask_names
      end

      sig { params(name: String).returns(T::Boolean) }
      def self.cask_name?(name)
        ensure_cask_data!
        return cache["cask_hashes"].key?(name) if cache.key?("cask_hashes")

        cache["packages_index"].cask_name?(name)
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_renames
        ensure_cask_data!
        packages_value("cask_renames")
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_tap_migrations
        ensure_cask_data!
        packages_value("cask_tap_migrations")
      end

      sig { returns(String) }
      def self.cask_tap_git_head
        ensure_cask_data!
        packages_value("cask_tap_git_head")
      end
    end
  end
end

require "extend/os/api/internal"
