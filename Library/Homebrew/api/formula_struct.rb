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
        # Bottle info is serialized by serialize_bottle
        :bottle_checksums,
        :bottle_rebuild,
      ].freeze

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

      sig { params(bottle_tag: ::Utils::Bottles::Tag).returns(T.nilable(T::Hash[String, T.untyped])) }
      def serialize_bottle(bottle_tag: ::Utils::Bottles.tag)
        bottle_collector = ::Utils::Bottles::Collector.new
        bottle_checksums.each do |bottle_info|
          bottle_info = bottle_info.dup
          cellar = T.cast(bottle_info.delete(:cellar), T.nilable(T.any(String, Symbol))) || :any
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
        cellar = (self.class.stringify_symbol(bottle_spec.cellar) if bottle_spec.cellar != DEFAULT_CELLAR)

        {
          "rebuild"  => bottle_rebuild,
          "tag"      => tag,
          "cellar"   => cellar,
          "checksum" => bottle_spec.checksum.to_s,
        }
      end

      sig { params(bottle_tag: ::Utils::Bottles::Tag).returns(T::Hash[String, T.untyped]) }
      def serialize(bottle_tag: ::Utils::Bottles.tag)
        hash = self.class.decorator.all_props.filter_map do |prop|
          next if PREDICATES.any? { |predicate| prop == :"#{predicate}_present" }
          next if SKIP_SERIALIZATION.include?(prop)

          [prop.to_s, send(prop)]
        end.to_h

        hash["bottle"] = serialize_bottle(bottle_tag:)

        shared, head, stable = self.class.extract_shared_items(head_dependencies, stable_dependencies)
        hash["dependencies"] = shared
        hash["head_dependencies"] = head
        hash["stable_dependencies"] = stable

        shared, head, stable = self.class.extract_shared_items(head_uses_from_macos, stable_uses_from_macos)
        hash["uses_from_macos"] = shared
        hash["head_uses_from_macos"] = head
        hash["stable_uses_from_macos"] = stable

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

        if (bottle_hash = hash["bottle"])
          hash["bottle_present"] = true
          hash["bottle_rebuild"] = bottle_hash["rebuild"] if bottle_hash["rebuild"].present?

          tag = bottle_hash.fetch("tag", bottle_tag.to_sym)
          cellar = bottle_hash.fetch("cellar", DEFAULT_CELLAR)

          hash["bottle_checksums"] = [{ cellar: cellar, tag => bottle_hash["checksum"] }]
        else
          hash["bottle_present"] = false
        end

        ["dependencies", "uses_from_macos"].each do |key|
          next unless (shared_deps = hash[key])

          hash["head_#{key}"] ||= []
          hash["stable_#{key}"] ||= []

          shared_deps.each do |dep|
            hash["head_#{key}"] << dep
            hash["stable_#{key}"] << dep
          end
        end

        # *_url_args need to be in [String, Hash] format, but the hash may have been dropped if empty
        ["head", "stable"].each do |key|
          hash["#{key}_url_args"] = if (url_args = hash["#{key}_url_args"])
            hash["#{key}_present"] = true

            if url_args.length == 1
              [url_args[0], {}]
            else
              url_args
            end
          else
            hash["#{key}_present"] = false

            ["", {}]
          end
        end

        from_hash(hash)
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
          obj.start_with?(":") ? T.must(obj[1..]).to_sym : obj
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

      # Accepts several lists, and returns a list with the shared items,
      # followed by each individual list with the shared items removed.
      #
      #   extract_shared_items([1, 2, 3], [2, 3, 4, 5])            # => [[2, 3], [1], [2, 4, 5]]
      #   extract_shared_items([1, 2, 3], [2, 3, 4], [3, 4, 5]) # => [[3], [1, 2], [2, 4], [4, 5]]
      sig { params(items: T::Array[T.untyped]).returns(T::Array[T::Array[T.untyped]]) }
      def self.extract_shared_items(*items)
        return [] if items.empty?

        shared_items = items.reduce(items.first) do |shared, item_list|
          shared & item_list
        end || []

        remaining_items = items.map do |item_list|
          item_list - shared_items
        end

        [shared_items, *remaining_items]
      end
    end
  end
end
