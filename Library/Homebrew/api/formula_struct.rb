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
        :no_autobump_message,
        :pour_bottle,
        :service,
        :service_run,
        :service_name,
        :stable,
      ].freeze

      # `:codesign` and custom requirement classes are not supported.
      API_SUPPORTED_REQUIREMENTS = [:arch, :linux, :macos, :maximum_macos, :xcode].freeze
      private_constant :API_SUPPORTED_REQUIREMENTS

      DependencyArgs = T.type_alias do
        T.any(
          # Formula name: "foo"
          String,
          # Formula name and dependency type: { "foo" => :build }
          T::Hash[String, Symbol],
        )
      end

      RequirementArgs = T.type_alias do
        T.any(
          # Requirement name: :macos
          Symbol,
          # Requirement name and other info: { macos: :build }
          T::Hash[Symbol, T::Array[T.anything]],
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

      DependencyHash = T.type_alias do
        T::Hash[
          # Keys are strings of the dependency type (e.g. "dependencies", "build_dependencies")
          String,
          # Values are arrays of either:
          T::Array[
            T.any(
              # Formula name: "foo"
              String,
              # Hash like { "foo" => "build" } or { :foo => ["build", "test"] }
              T::Hash[
                String,
                T.any(String, T::Array[String]),
              ],
            ),
          ],
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
      const :bottle, T::Hash[String, T.anything], default: {}
      const :bottle_checksums, T::Array[T::Hash[Symbol, T.anything]], default: []
      const :bottle_rebuild, Integer, default: 0
      const :caveats, T.nilable(String)
      const :conflicts, T::Array[[String, T::Hash[Symbol, String]]], default: []
      const :deprecate_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :desc, String
      const :disable_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :head_url_args, [String, T::Hash[Symbol, T.anything]]
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
      const :ruby_source_path, String
      const :service_args, T::Array[[Symbol, BasicObject]], default: []
      const :service_name_args, T::Hash[Symbol, String], default: {}
      const :service_run_args, T::Array[Homebrew::Service::RunParam], default: []
      const :service_run_kwargs, T::Hash[Symbol, Homebrew::Service::RunParam], default: {}
      const :stable_checksum, T.nilable(String)
      const :stable_url_args, [String, T::Hash[Symbol, T.anything]]
      const :stable_version, String
      const :tap_git_head, String
      const :version_scheme, Integer, default: 0
      const :versioned_formulae, T::Array[String], default: []

      sig { returns(T::Array[T.any(DependencyArgs, RequirementArgs)]) }
      def head_dependencies
        spec_dependencies(:head) + spec_requirements(:head)
      end

      sig { returns(T::Array[T.any(DependencyArgs, RequirementArgs)]) }
      def stable_dependencies
        spec_dependencies(:stable) + spec_requirements(:stable)
      end

      sig { returns(T::Array[UsesFromMacOSArgs]) }
      def head_uses_from_macos
        spec_uses_from_macos(:head)
      end

      sig { returns(T::Array[UsesFromMacOSArgs]) }
      def stable_uses_from_macos
        spec_uses_from_macos(:stable)
      end

      private

      const :stable_dependency_hash, DependencyHash, default: {}
      const :head_dependency_hash, DependencyHash, default: {}
      const :requirements_array, T::Array[T::Hash[String, T.untyped]], default: []

      sig { params(spec: Symbol).returns(T::Array[DependencyArgs]) }
      def spec_dependencies(spec)
        deps_hash = send("#{spec}_dependency_hash")
        dependencies = deps_hash.fetch("dependencies", [])
        dependencies + [:build, :test, :recommended, :optional].filter_map do |type|
          deps_hash["#{type}_dependencies"]&.map do |dep|
            { dep => type }
          end
        end.flatten(1)
      end

      sig { params(spec: Symbol).returns(T::Array[UsesFromMacOSArgs]) }
      def spec_uses_from_macos(spec)
        deps_hash = send("#{spec}_dependency_hash")
        zipped_array = deps_hash["uses_from_macos"]&.zip(deps_hash["uses_from_macos_bounds"])
        return [] unless zipped_array

        zipped_array.map do |entry, bounds|
          bounds ||= {}
          bounds = bounds.transform_keys(&:to_sym).transform_values(&:to_sym)

          if entry.is_a?(Hash)
            # The key is the dependency name, the value is the dep type. Only the type should be a symbol
            entry = entry.deep_transform_values(&:to_sym)
            # When passing both a dep type and bounds, uses_from_macos expects them both in the first argument
            entry = entry.merge(bounds)
            [entry, {}]
          else
            [entry, bounds]
          end
        end
      end

      sig { params(spec: Symbol).returns(T::Array[RequirementArgs]) }
      def spec_requirements(spec)
        requirements_array.filter_map do |req|
          next unless req["specs"].include?(spec.to_s)

          req_name = req["name"].to_sym
          next if API_SUPPORTED_REQUIREMENTS.exclude?(req_name)

          req_version = case req_name
          when :arch
            req["version"]&.to_sym
          when :macos, :maximum_macos
            MacOSVersion::SYMBOLS.key(req["version"])
          else
            req["version"]
          end

          req_tags = []
          req_tags << req_version if req_version.present?
          req_tags += req["contexts"]&.map do |tag|
            case tag
            when String
              tag.to_sym
            when Hash
              tag.deep_transform_keys(&:to_sym)
            else
              tag
            end
          end

          if req_tags.empty?
            req_name
          else
            { req_name => req_tags }
          end
        end
      end
    end
  end
end
