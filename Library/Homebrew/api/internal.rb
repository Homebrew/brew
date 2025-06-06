# typed: strict
# frozen_string_literal: true

require "extend/cachable"
require "api/download"
require "formula_stub"

module Homebrew
  module API
    # Helper functions for using the JSON internal API.
    module Internal
      extend Cachable

      private_class_method :cache

      sig { returns(String) }
      def self.endpoint
        "internal/formula.#{SimulateSystem.current_tag}.jws.json"
      end

      sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      def self.formula(name)
        return cache["formula_stubs"][name] if cache.key?("formula_stubs") && cache["formula_stubs"].key?(name)

        stub_array = all_formula_stubs[name]
        raise "No formula stub found for #{name}" unless stub_array

        formula_stub = Homebrew::FormulaStub.from_array name, stub_array

        tag = Utils::Bottles.tag
        bottle_specification = BottleSpecification.new
        bottle_specification.tap = Homebrew::DEFAULT_REPOSITORY
        bottle_specification.rebuild formula_stub.rebuild
        bottle_specification.sha256 tag.to_sym => formula_stub.sha256

        bottle = Bottle.new(formula_stub, bottle_specification, tag)
        bottle_manifest_resource = T.must(bottle.github_packages_manifest_resource)

        begin
          bottle_manifest_resource.fetch
          formula_json = bottle_manifest_resource.formula_json

          cache["formula_stubs"][name] = formula_json
          formula_json
        rescue Resource::BottleManifest::Error
          opoo "Falling back to API fetch for #{name}"
          Homebrew::API.fetch "formula/#{name}.json"
        end
      end

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/endpoint
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_formula_stubs, updated = Homebrew::API.fetch_json_api_file endpoint
        cache["formula_stubs"] = {}
        cache["all_formula_stubs"] = json_formula_stubs
        updated
      end
      private_class_method :download_and_cache_data!

      sig { returns(T::Hash[String, [String, Integer, T.nilable(String)]]) }
      def self.all_formula_stubs
        download_and_cache_data! unless cache.key?("all_formula_stubs")

        cache["all_formula_stubs"]
      end
    end
  end
end
