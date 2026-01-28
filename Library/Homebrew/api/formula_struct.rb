# typed: strict
# frozen_string_literal: true

require "service"
require "utils/spdx"

module Homebrew
  module API
    class FormulaStruct < T::Struct
      sig { params(formula_hash: T::Hash[String, T.untyped]).returns(FormulaStruct) }
      def self.from_hash(formula_hash)
        formula_hash = formula_hash.transform_keys(&:to_sym)
                                   .slice(*decorator.all_props)
                                   .compact_blank
        new(**formula_hash)
      end

      PREDICATES = [
        :bottle,
        :deprecate,
        :disable,
        :head,
        :keg_only,
        :no_autobump,
        :pour_bottle,
        :service,
        :service_run,
        :service_name,
        :stable,
      ].freeze

      DependsOnArgs = T.type_alias do
        T.any(
          # Dependencies
          T.any(
            # Formula name: "foo"
            String,
            # Formula name and dependency type: { "foo" => :build }
            T::Hash[String, Symbol],
          ),
          # Requirements
          T.any(
            # Requirement name: :macos
            Symbol,
            # Requirement name and other info: { macos: :build }
            T::Hash[Symbol, T::Array[T.anything]],
          ),
        )
      end

      UsesFromMacOSArgs = T.type_alias do
        [
          T.any(
            # Formula name: "foo"
            String,
            # Formula name and dependency type: { "foo" => :build }
            # Formula name, dependency type, and version bounds: { "foo" => :build, since: :catalina }
            T::Hash[T.any(String, Symbol), T.any(Symbol, T::Array[Symbol])],
          ),
          # If the first argument is only a name, this argument contains the version bounds: { since: :catalina }
          T::Hash[Symbol, Symbol],
        ]
      end

      PREDICATES.each do |predicate_name|
        present_method_name = :"#{predicate_name}_present"
        predicate_method_name = :"#{predicate_name}?"

        const present_method_name, T::Boolean, default: false

        define_method(predicate_method_name) do
          send(present_method_name)
        end
      end

      # Changes to this struct must be mirrored in Homebrew::API::Formula.generate_formula_struct_hash
      const :aliases, T::Array[String], default: []
      const :bottle_checksums, T::Array[T::Hash[Symbol, T.anything]], default: []
      const :bottle_rebuild, Integer, default: 0
      const :caveats, T.nilable(String)
      const :conflicts, T::Array[[String, T::Hash[Symbol, String]]], default: []
      const :deprecate_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :desc, String
      const :disable_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :head_dependencies, T::Array[DependsOnArgs], default: []
      const :head_url_args, [String, T::Hash[Symbol, T.anything]]
      const :head_uses_from_macos, T::Array[UsesFromMacOSArgs], default: []
      const :homepage, String
      const :keg_only_args, T::Array[T.any(String, Symbol)], default: []
      const :license, SPDX::LicenseExpression
      const :link_overwrite_paths, T::Array[String], default: []
      const :no_autobump_args, T::Hash[Symbol, T.any(String, Symbol)], default: {}
      const :oldnames, T::Array[String], default: []
      const :post_install_defined, T::Boolean, default: true
      const :pour_bottle_args, T::Hash[Symbol, Symbol], default: {}
      const :revision, Integer, default: 0
      const :ruby_source_checksum, String
      const :service_args, T::Array[[Symbol, BasicObject]], default: []
      const :service_name_args, T::Hash[Symbol, String], default: {}
      const :service_run_args, T::Array[Homebrew::Service::RunParam], default: []
      const :service_run_kwargs, T::Hash[Symbol, Homebrew::Service::RunParam], default: {}
      const :stable_dependencies, T::Array[DependsOnArgs], default: []
      const :stable_checksum, T.nilable(String)
      const :stable_url_args, [String, T::Hash[Symbol, T.anything]]
      const :stable_uses_from_macos, T::Array[UsesFromMacOSArgs], default: []
      const :stable_version, String
      const :version_scheme, Integer, default: 0
      const :versioned_formulae, T::Array[String], default: []
    end
  end
end
