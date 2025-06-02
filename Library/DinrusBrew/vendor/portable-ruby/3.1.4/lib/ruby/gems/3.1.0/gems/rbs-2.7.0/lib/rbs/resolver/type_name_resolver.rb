# frozen_string_literal: true

module RBS
  module Resolver
    class TypeNameResolver
      attr_reader :all_names
      attr_reader :cache

      def initialize(env)
        @all_names = Set[]
        @cache = {}

        all_names.merge(env.class_decls.keys)
        all_names.merge(env.interface_decls.keys)
        all_names.merge(env.alias_decls.keys)
      end

      def try_cache(query)
        cache.fetch(query) do
          result = yield
          cache[query] = result
        end
      end

      def resolve(type_name, context:)
        if type_name.absolute?
          return type_name
        end

        try_cache([type_name, context]) do
          resolve_in(type_name, context)
        end
      end

      def resolve_in(type_name, context)
        if context
          parent, child = context
          case child
          when false
            resolve_in(type_name, parent)
          when TypeName
            name = type_name.with_prefix(child.to_namespace)
            has_name?(name) || resolve_in(type_name, parent)
          end
        else
          has_name?(type_name.absolute!)
        end
      end

      def has_name?(full_name)
        if all_names.include?(full_name)
          full_name
        end
      end
    end
  end
end
