# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "download_queue"
require "formula_stub"

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

      sig { params(name: String).returns(Homebrew::FormulaStub) }
      def self.formula_stub(name)
        return cache["formula_stubs"][name] if cache.key?("formula_stubs") && cache["formula_stubs"].key?(name)

        stub_array = all_formula_arrays[name]
        raise "No formula stub found for #{name}" unless stub_array

        Homebrew::FormulaStub.new(
          name:           name,
          pkg_version:    PkgVersion.parse(stub_array[0]),
          version_scheme: 0,
          rebuild:        stub_array[1],
          sha256:         stub_array[2],
        )
      end

      # sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      # def self.formula(name)
      #   return cache["formula_stubs"][name] if cache.key?("formula_stubs") && cache["formula_stubs"].key?(name)

      #   stub_array = all_formula_arrays[name]
      #   raise "No formula stub found for #{name}" unless stub_array

      #   formula_stub = Homebrew::FormulaStub.new(
      #     name:           name,
      #     pkg_version:    PkgVersion.parse(stub_array[0]),
      #     version_scheme: 0,
      #     rebuild:        stub_array[1],
      #     sha256:         stub_array[2],
      #   )

      #   tag = Utils::Bottles.tag
      #   bottle_specification = BottleSpecification.new
      #   bottle_specification.tap = Homebrew::DEFAULT_REPOSITORY
      #   bottle_specification.rebuild formula_stub.rebuild
      #   bottle_specification.sha256 tag.to_sym => formula_stub.sha256

      #   bottle = Bottle.new(formula_stub, bottle_specification, tag)
      #   bottle_manifest_resource = T.must(bottle.github_packages_manifest_resource)

      #   begin
      #     bottle_manifest_resource.fetch
      #     formula_json = bottle_manifest_resource.formula_json

      #     cache["formula_stubs"][name] = formula_json
      #     formula_json
      #   rescue Resource::BottleManifest::Error
      #     opoo "Falling back to API fetch for #{name}"
      #     Homebrew::API.fetch "formula/#{name}.json"
      #   end
      # end

      sig { returns(Pathname) }
      def self.cached_formula_json_file_path
        HOMEBREW_CACHE_API/formula_endpoint
      end

      sig { returns(Pathname) }
      def self.cached_cask_json_file_path
        HOMEBREW_CACHE_API/cask_endpoint
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_formula_api!(download_queue: nil, stale_seconds: Homebrew::EnvConfig.api_auto_update_secs.to_i)
        Homebrew::API.fetch_json_api_file formula_endpoint, stale_seconds:, download_queue:
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: Integer)
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_cask_api!(download_queue: nil, stale_seconds: Homebrew::EnvConfig.api_auto_update_secs.to_i)
        Homebrew::API.fetch_json_api_file cask_endpoint, stale_seconds:, download_queue:
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_formula_data!
        json_formula_stubs, updated = fetch_formula_api!
        cache["formula_stubs"] = {}
        cache["all_formula_arrays"] = json_formula_stubs
        updated
      end
      private_class_method :download_and_cache_formula_data!

      sig { returns(T::Boolean) }
      def self.download_and_cache_cask_data!
        json_cask_stubs, updated = fetch_cask_api!
        cache["cask_stubs"] = {}
        cache["all_cask_stubs"] = json_cask_stubs
        updated
      end
      private_class_method :download_and_cache_cask_data!

      sig { returns(T::Hash[String, [String, Integer, T.nilable(String)]]) }
      def self.all_formula_arrays
        download_and_cache_formula_data! unless cache.key?("all_formula_arrays")

        cache["all_formula_arrays"]
      end
    end
  end
end
