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

      SKIP_SERIALIZATION = [
        # Bottle checksums have special serialization done by the serialize_bottle method
        :bottle_checksums,
      ].freeze

      SPECS = [:head, :stable].freeze

      # :any_skip_relocation is the most common in homebrew/core
      DEFAULT_CELLAR = :any_skip_relocation

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
      const :bottle_checksums, T::Array[T::Hash[Symbol, T.any(String, Symbol)]], default: []
      const :bottle_rebuild, Integer, default: 0
      const :caveats, T.nilable(String)
      const :conflicts, T::Array[[String, T::Hash[Symbol, String]]], default: []
      const :deprecate_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :desc, String
      const :disable_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :head_dependencies, T::Array[DependsOnArgs], default: []
      const :head_url_args, [String, T::Hash[Symbol, T.anything]], default: ["", {}]
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
      const :stable_url_args, [String, T::Hash[Symbol, T.anything]], default: ["", {}]
      const :stable_uses_from_macos, T::Array[UsesFromMacOSArgs], default: []
      const :stable_version, String
      const :version_scheme, Integer, default: 0
      const :versioned_formulae, T::Array[String], default: []

      sig { params(other: T.anything).returns(T::Boolean) }
      def ==(other)
        case other
        when FormulaStruct
          serialize == other.serialize
        else
          false
        end
      end

      sig { params(bottle_tag: ::Utils::Bottles::Tag).returns(T.nilable(T::Hash[String, T.untyped])) }
      def serialize_bottle(bottle_tag: ::Utils::Bottles.tag)
        bottle_collector = ::Utils::Bottles::Collector.new
        bottle_checksums.each do |bottle_info|
          bottle_info = bottle_info.dup
          cellar = bottle_info.delete(:cellar) || :any
          tag = T.must(bottle_info.keys.first)
          checksum = T.cast(bottle_info.values.first, String)

          bottle_collector.add(
            ::Utils::Bottles::Tag.from_symbol(tag),
            checksum: Checksum.new(checksum),
            cellar:,
          )
        end
        return unless (bottle_spec = bottle_collector.specification_for(bottle_tag))

        tag = (bottle_spec.tag if bottle_spec.tag != bottle_tag)
        cellar = (bottle_spec.cellar if bottle_spec.cellar != DEFAULT_CELLAR)

        {
          "bottle_tag"      => tag&.to_sym,
          "bottle_cellar"   => cellar,
          "bottle_checksum" => bottle_spec.checksum.to_s,
        }
      end

      sig { params(bottle_tag: ::Utils::Bottles::Tag).returns(T::Hash[String, T.untyped]) }
      def serialize(bottle_tag: ::Utils::Bottles.tag)
        hash = self.class.decorator.all_props.filter_map do |prop|
          next if PREDICATES.any? { |predicate| prop == :"#{predicate}_present" }
          next if SKIP_SERIALIZATION.include?(prop)

          [prop.to_s, send(prop)]
        end.to_h

        if (bottle_hash = serialize_bottle(bottle_tag:))
          hash = hash.merge(bottle_hash)
        end

        hash = self.class.deep_stringify_symbols(hash)
        self.class.deep_compact_blank(hash)
      end

      sig { params(hash: T::Hash[String, T.untyped], bottle_tag: ::Utils::Bottles::Tag).returns(FormulaStruct) }
      def self.deserialize(hash, bottle_tag: ::Utils::Bottles.tag)
        hash = deep_unstringify_symbols(hash)

        # Items that don't follow the `hash["foo_present"] = hash["foo_args"].present?` pattern are overridden below
        PREDICATES.each do |name|
          hash["#{name}_present"] = hash["#{name}_args"].present?
        end

        if (bottle_checksum = hash["bottle_checksum"])
          tag = hash.fetch("bottle_tag", bottle_tag.to_sym)
          cellar = hash.fetch("bottle_cellar", DEFAULT_CELLAR)

          hash["bottle_present"] = true
          hash["bottle_checksums"] = [{ cellar: cellar, tag => bottle_checksum }]
        else
          hash["bottle_present"] = false
        end

        # *_url_args need to be in [String, Hash] format, but the hash may have been dropped if empty
        SPECS.each do |key|
          if (url_args = hash["#{key}_url_args"])
            hash["#{key}_present"] = true
            hash["#{key}_url_args"] = format_arg_pair(url_args, last: {})
          else
            hash["#{key}_present"] = false
          end

          next unless (uses_from_macos = hash["#{key}_uses_from_macos"])

          hash["#{key}_uses_from_macos"] = uses_from_macos.map do |args|
            format_arg_pair(args, last: {})
          end
        end

        hash["service_args"] = if (service_args = hash["service_args"])
          service_args.map { |service_arg| format_arg_pair(service_arg, last: nil) }
        end

        hash["conflicts"] = if (conflicts = hash["conflicts"])
          conflicts.map { |conflict| format_arg_pair(conflict, last: {}) }
        end

        from_hash(hash)
      end

      # Format argument pairs into proper [first, last] format if serialization has removed some elements.
      # Pass a default value for last to be used when only one element is present.
      #
      #  format_arg_pair(["foo"], last: {})                       # => ["foo", {}]
      #  format_arg_pair([{ "foo" => :build }], last: {})         # => [{ "foo" => :build }, {}]
      #  format_arg_pair(["foo", { since: :catalina }], last: {}) # => ["foo", { since: :catalina }]
      sig {
        type_parameters(:U, :V)
          .params(
            args: T.any([T.type_parameter(:U)], [T.type_parameter(:U), T.type_parameter(:V)]),
            last: T.type_parameter(:V),
          ).returns([T.type_parameter(:U), T.type_parameter(:V)])
      }
      def self.format_arg_pair(args, last:)
        args = case args
        in [elem]
          [elem, last]
        in [elem1, elem2]
          [elem1, elem2]
        end

        # The case above is exhaustive so args will never be nil, but sorbet cannot infer that.
        T.must(args)
      end

      # Converts a symbol to a string starting with `:`, otherwise returns the input.
      #
      #   stringify_symbol(:example)  # => ":example"
      #   stringify_symbol("example") # => "example"
      sig { params(value: T.any(String, Symbol)).returns(T.nilable(String)) }
      def self.stringify_symbol(value)
        return ":#{value}" if value.is_a?(Symbol)

        value
      end

      sig { params(obj: T.untyped).returns(T.untyped) }
      def self.deep_stringify_symbols(obj)
        case obj
        when String
          # Escape leading : or \ to avoid confusion with stringified symbols
          # ":foo" -> "\:foo"
          # "\foo" -> "\\foo"
          if obj.start_with?(":", "\\")
            "\\#{obj}"
          else
            obj
          end
        when Symbol
          ":#{obj}"
        when Hash
          obj.to_h { |k, v| [deep_stringify_symbols(k), deep_stringify_symbols(v)] }
        when Array
          obj.map { |v| deep_stringify_symbols(v) }
        else
          obj
        end
      end

      sig { params(obj: T.untyped).returns(T.untyped) }
      def self.deep_unstringify_symbols(obj)
        case obj
        when String
          if obj.start_with?("\\")
            obj[1..]
          elsif obj.start_with?(":")
            T.must(obj[1..]).to_sym
          else
            obj
          end
        when Hash
          obj.to_h { |k, v| [deep_unstringify_symbols(k), deep_unstringify_symbols(v)] }
        when Array
          obj.map { |v| deep_unstringify_symbols(v) }
        else
          obj
        end
      end

      sig {
        type_parameters(:U)
          .params(obj: T.all(T.type_parameter(:U), Object))
          .returns(T.nilable(T.type_parameter(:U)))
      }
      def self.deep_compact_blank(obj)
        obj = case obj
        when Hash
          obj.transform_values { |v| deep_compact_blank(v) }
             .compact
        when Array
          obj.filter_map { |v| deep_compact_blank(v) }
        else
          obj
        end

        return if obj.blank? || (obj.is_a?(Numeric) && obj.zero?)

        obj
      end
    end
  end
end
