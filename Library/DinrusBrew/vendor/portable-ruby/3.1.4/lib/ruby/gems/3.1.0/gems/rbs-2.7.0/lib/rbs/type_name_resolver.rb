# frozen_string_literal: true

module RBS
  class TypeNameResolver
    Query = _ = Struct.new(:type_name, :context, keyword_init: true)

    attr_reader :all_names
    attr_reader :cache

    def initialize()
      @all_names = Set[]
      @cache = {}
    end

    def self.from_env(env)
      new.add_names(env.class_decls.keys)
        .add_names(env.interface_decls.keys)
        .add_names(env.alias_decls.keys)
    end

    def add_names(names)
      all_names.merge(names)
      self
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

      query = Query.new(type_name: type_name, context: context)
      try_cache(query) do
        path_head, *path_tail = type_name.split
        raise unless path_head

        name_head = TypeName.new(name: path_head, namespace: Namespace.empty)

        absolute_head = context.find do |namespace|
          # @type break: TypeName
          full_name = name_head.with_prefix(namespace)
          has_name?(full_name) and break full_name
        end

        case absolute_head
        when TypeName
          has_name?(Namespace.new(path: absolute_head.to_namespace.path.push(*path_tail), absolute: true).to_type_name)
        when Namespace
          # This cannot happen because the `context.find` doesn't return a Namespace.
          raise
        end
      end
    end

    def has_name?(full_name)
      if all_names.include?(full_name)
        full_name
      end
    end
  end
end
