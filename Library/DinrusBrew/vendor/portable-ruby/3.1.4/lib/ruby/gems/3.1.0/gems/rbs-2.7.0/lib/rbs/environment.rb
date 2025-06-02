# frozen_string_literal: true

module RBS
  class Environment
    attr_reader :declarations

    attr_reader :class_decls
    attr_reader :interface_decls
    attr_reader :alias_decls
    attr_reader :constant_decls
    attr_reader :global_decls

    module ContextUtil
      def calculate_context(decls)
        decls.each.with_object([Namespace.root]) do |decl, array|
          first = array.first or raise
          array.unshift(first + decl.name.to_namespace)
        end
      end
    end

    class MultiEntry
      D = _ = Struct.new(:decl, :outer, keyword_init: true) do
        # @implements D[M]

        include ContextUtil

        def context
          @context ||= calculate_context(outer + [decl])
        end
      end

      attr_reader :name
      attr_reader :decls

      def initialize(name:)
        @name = name
        @decls = []
      end

      def insert(decl:, outer:)
        decls << D.new(decl: decl, outer: outer)
        @primary = nil
      end

      def validate_type_params
        unless decls.empty?
          hd_decl, *tl_decls = decls
          raise unless hd_decl

          hd_params = hd_decl.decl.type_params

          tl_decls.each do |tl_decl|
            tl_params = tl_decl.decl.type_params

            unless compatible_params?(hd_params, tl_params)
              raise GenericParameterMismatchError.new(name: name, decl: _ = tl_decl.decl)
            end
          end
        end
      end

      def compatible_params?(ps1, ps2)
        if ps1.size == ps2.size
          ps1 == AST::TypeParam.rename(ps2, new_names: ps1.map(&:name))
        end
      end

      def type_params
        primary.decl.type_params
      end

      def primary
        raise "Not implemented"
      end
    end

    class ModuleEntry < MultiEntry
      def self_types
        decls.flat_map do |d|
          d.decl.self_types
        end.uniq
      end

      def primary
        @primary ||= begin
                       validate_type_params
                       decls.first or raise("decls cannot be empty")
                     end
      end
    end

    def foo
      a = [1].sample()
      return unless a
      a + 1
    end

    class ClassEntry < MultiEntry
      def primary
        @primary ||= begin
                       validate_type_params
                       decls.find {|d| d.decl.super_class } || decls.first or raise("decls cannot be empty")
                     end
      end
    end

    class SingleEntry
      attr_reader :name
      attr_reader :outer
      attr_reader :decl

      def initialize(name:, decl:, outer:)
        @name = name
        @decl = decl
        @outer = outer
      end

      include ContextUtil

      def context
        @context = calculate_context(outer)
      end
    end

    def initialize
      @buffers = []
      @declarations = []

      @class_decls = {}
      @interface_decls = {}
      @alias_decls = {}
      @constant_decls = {}
      @global_decls = {}
    end

    def initialize_copy(other)
      @buffers = other.buffers.dup
      @declarations = other.declarations.dup

      @class_decls = other.class_decls.dup
      @interface_decls = other.interface_decls.dup
      @alias_decls = other.alias_decls.dup
      @constant_decls = other.constant_decls.dup
      @global_decls = other.global_decls.dup
    end

    def self.from_loader(loader)
      self.new.tap do |env|
        loader.load(env: env)
      end
    end

    def cache_name(cache, name:, decl:, outer:)
      if cache.key?(name)
        raise DuplicatedDeclarationError.new(_ = name, _ = decl, _ = cache[name].decl)
      end

      cache[name] = SingleEntry.new(name: name, decl: decl, outer: outer)
    end

    def insert_decl(decl, outer:, namespace:)
      case decl
      when AST::Declarations::Class, AST::Declarations::Module
        name = decl.name.with_prefix(namespace)

        if constant_decls.key?(name)
          raise DuplicatedDeclarationError.new(name, decl, constant_decls[name].decl)
        end

        unless class_decls.key?(name)
          case decl
          when AST::Declarations::Class
            class_decls[name] ||= ClassEntry.new(name: name)
          when AST::Declarations::Module
            class_decls[name] ||= ModuleEntry.new(name: name)
          end
        end

        existing_entry = class_decls[name]

        case
        when decl.is_a?(AST::Declarations::Module) && existing_entry.is_a?(ModuleEntry)
          # @type var existing_entry: ModuleEntry
          # @type var decl: AST::Declarations::Module
          existing_entry.insert(decl: decl, outer: outer)
        when decl.is_a?(AST::Declarations::Class) && existing_entry.is_a?(ClassEntry)
          # @type var existing_entry: ClassEntry
          # @type var decl: AST::Declarations::Class
          existing_entry.insert(decl: decl, outer: outer)
        else
          raise DuplicatedDeclarationError.new(name, decl, existing_entry.decls[0].decl)
        end

        prefix = outer + [decl]
        ns = name.to_namespace
        decl.each_decl do |d|
          insert_decl(d, outer: prefix, namespace: ns)
        end

      when AST::Declarations::Interface
        cache_name interface_decls, name: decl.name.with_prefix(namespace), decl: decl, outer: outer

      when AST::Declarations::Alias
        cache_name alias_decls, name: decl.name.with_prefix(namespace), decl: decl, outer: outer

      when AST::Declarations::Constant
        name = decl.name.with_prefix(namespace)

        if class_decls.key?(name)
          raise DuplicatedDeclarationError.new(name, decl, class_decls[name].decls[0].decl)
        end

        cache_name constant_decls, name: name, decl: decl, outer: outer

      when AST::Declarations::Global
        cache_name global_decls, name: decl.name, decl: decl, outer: outer
      end
    end

    def <<(decl)
      declarations << decl
      insert_decl(decl, outer: [], namespace: Namespace.root)
      self
    end

    def validate_type_params
      class_decls.each_value do |decl|
        decl.primary
      end
    end

    def resolve_type_names(only: nil)
      resolver = TypeNameResolver.from_env(self)
      env = Environment.new()

      declarations.each do |decl|
        if only && !only.member?(decl)
          env << decl
        else
          env << resolve_declaration(resolver, decl, outer: [], prefix: Namespace.root)
        end
      end

      env
    end

    def resolve_declaration(resolver, decl, outer:, prefix:)
      if decl.is_a?(AST::Declarations::Global)
        # @type var decl: AST::Declarations::Global
        return AST::Declarations::Global.new(
          name: decl.name,
          type: absolute_type(resolver, decl.type, context: [Namespace.root]),
          location: decl.location,
          comment: decl.comment
        )
      end

      context = (outer + [decl]).each.with_object([Namespace.root]) do |decl, array|
        head = array.first or raise
        array.unshift(head + decl.name.to_namespace)
      end

      outer_context = context.drop(1)

      case decl
      when AST::Declarations::Class
        outer_ = outer + [decl]
        prefix_ = prefix + decl.name.to_namespace
        AST::Declarations::Class.new(
          name: decl.name.with_prefix(prefix),
          type_params: resolve_type_params(resolver, decl.type_params, context: context),
          super_class: decl.super_class&.yield_self do |super_class|
            AST::Declarations::Class::Super.new(
              name: absolute_type_name(resolver, super_class.name, context: outer_context),
              args: super_class.args.map {|type| absolute_type(resolver, type, context: outer_context) },
              location: super_class.location
            )
          end,
          members: decl.members.map do |member|
            case member
            when AST::Members::Base
              resolve_member(resolver, member, context: context)
            when AST::Declarations::Base
              resolve_declaration(
                resolver,
                member,
                outer: outer_,
                prefix: prefix_
              )
            else
              raise
            end
          end,
          location: decl.location,
          annotations: decl.annotations,
          comment: decl.comment
        )
      when AST::Declarations::Module
        outer_ = outer + [decl]
        prefix_ = prefix + decl.name.to_namespace
        AST::Declarations::Module.new(
          name: decl.name.with_prefix(prefix),
          type_params: resolve_type_params(resolver, decl.type_params, context: context),
          self_types: decl.self_types.map do |module_self|
            AST::Declarations::Module::Self.new(
              name: absolute_type_name(resolver, module_self.name, context: context),
              args: module_self.args.map {|type| absolute_type(resolver, type, context: context) },
              location: module_self.location
            )
          end,
          members: decl.members.map do |member|
            case member
            when AST::Members::Base
              resolve_member(resolver, member, context: context)
            when AST::Declarations::Base
              resolve_declaration(
                resolver,
                member,
                outer: outer_,
                prefix: prefix_
              )
            else
              raise
            end
          end,
          location: decl.location,
          annotations: decl.annotations,
          comment: decl.comment
        )
      when AST::Declarations::Interface
        AST::Declarations::Interface.new(
          name: decl.name.with_prefix(prefix),
          type_params: resolve_type_params(resolver, decl.type_params, context: context),
          members: decl.members.map do |member|
            resolve_member(resolver, member, context: context)
          end,
          comment: decl.comment,
          location: decl.location,
          annotations: decl.annotations
        )
      when AST::Declarations::Alias
        AST::Declarations::Alias.new(
          name: decl.name.with_prefix(prefix),
          type_params: resolve_type_params(resolver, decl.type_params, context: context),
          type: absolute_type(resolver, decl.type, context: context),
          location: decl.location,
          annotations: decl.annotations,
          comment: decl.comment
        )

      when AST::Declarations::Constant
        AST::Declarations::Constant.new(
          name: decl.name.with_prefix(prefix),
          type: absolute_type(resolver, decl.type, context: context),
          location: decl.location,
          comment: decl.comment
        )
      end
    end

    def resolve_member(resolver, member, context:)
      case member
      when AST::Members::MethodDefinition
        AST::Members::MethodDefinition.new(
          name: member.name,
          kind: member.kind,
          types: member.types.map do |type|
            resolve_method_type(resolver, type, context: context)
          end,
          comment: member.comment,
          overload: member.overload?,
          annotations: member.annotations,
          location: member.location,
          visibility: member.visibility
        )
      when AST::Members::AttrAccessor
        AST::Members::AttrAccessor.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          kind: member.kind,
          annotations: member.annotations,
          comment: member.comment,
          location: member.location,
          ivar_name: member.ivar_name,
          visibility: member.visibility
        )
      when AST::Members::AttrReader
        AST::Members::AttrReader.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          kind: member.kind,
          annotations: member.annotations,
          comment: member.comment,
          location: member.location,
          ivar_name: member.ivar_name,
          visibility: member.visibility
        )
      when AST::Members::AttrWriter
        AST::Members::AttrWriter.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          kind: member.kind,
          annotations: member.annotations,
          comment: member.comment,
          location: member.location,
          ivar_name: member.ivar_name,
          visibility: member.visibility
        )
      when AST::Members::InstanceVariable
        AST::Members::InstanceVariable.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          comment: member.comment,
          location: member.location
        )
      when AST::Members::ClassInstanceVariable
        AST::Members::ClassInstanceVariable.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          comment: member.comment,
          location: member.location
        )
      when AST::Members::ClassVariable
        AST::Members::ClassVariable.new(
          name: member.name,
          type: absolute_type(resolver, member.type, context: context),
          comment: member.comment,
          location: member.location
        )
      when AST::Members::Include
        AST::Members::Include.new(
          name: absolute_type_name(resolver, member.name, context: context),
          args: member.args.map {|type| absolute_type(resolver, type, context: context) },
          comment: member.comment,
          location: member.location,
          annotations: member.annotations
        )
      when AST::Members::Extend
        AST::Members::Extend.new(
          name: absolute_type_name(resolver, member.name, context: context),
          args: member.args.map {|type| absolute_type(resolver, type, context: context) },
          comment: member.comment,
          location: member.location,
          annotations: member.annotations
        )
      when AST::Members::Prepend
        AST::Members::Prepend.new(
          name: absolute_type_name(resolver, member.name, context: context),
          args: member.args.map {|type| absolute_type(resolver, type, context: context) },
          comment: member.comment,
          location: member.location,
          annotations: member.annotations
        )
      else
        member
      end
    end

    def resolve_method_type(resolver, type, context:)
      type.map_type do |ty|
        absolute_type(resolver, ty, context: context)
      end.map_type_bound do |bound|
        _ = absolute_type(resolver, bound, context: context)
      end
    end

    def resolve_type_params(resolver, params, context:)
      params.map do |param|
        param.map_type {|type| _ = absolute_type(resolver, type, context: context) }
      end
    end

    def absolute_type_name(resolver, type_name, context:)
      resolver.resolve(type_name, context: context) || type_name
    end

    def absolute_type(resolver, type, context:)
      type.map_type_name do |name, _, _|
        absolute_type_name(resolver, name, context: context)
      end
    end

    def inspect
      ivars = %i[@declarations @class_decls @interface_decls @alias_decls @constant_decls @global_decls]
      "\#<RBS::Environment #{ivars.map { |iv| "#{iv}=(#{instance_variable_get(iv).size} items)"}.join(' ')}>"
    end

    def buffers
      buffers_decls.keys.compact
    end

    def buffers_decls
      # @type var hash: Hash[Buffer, Array[AST::Declarations::t]]
      hash = {}

      declarations.each do |decl|
        location = decl.location or next
        (hash[location.buffer] ||= []) << decl
      end

      hash
    end

    def reject
      env = Environment.new

      declarations.each do |decl|
        unless yield(decl)
          env << decl
        end
      end

      env
    end
  end
end
