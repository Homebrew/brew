# frozen_string_literal: true

module RBS
  module Resolver
    class ConstantResolver
      class Table
        attr_reader :children_table, :toplevel
        attr_reader :constants_table

        def initialize(environment)
          @children_table = {}
          @toplevel = {}

          @constants_table = {}

          environment.class_decls.each_key do |name|
            children_table[name] = {}
          end

          environment.class_decls.each do |name, entry|
            unless name.namespace.empty?
              parent = name.namespace.to_type_name

              table = children_table[parent] or raise
              constant = constant_of_module(name, entry)
            else
              table = toplevel
              constant = constant_of_module(name, entry)
            end

            table[name.name] = constant
            constants_table[name] = constant
          end

          environment.constant_decls.each do |name, entry|
            unless name.namespace.empty?
              parent = name.namespace.to_type_name

              table = children_table[parent] or raise
              constant = constant_of_constant(name, entry)
            else
              table = toplevel
              constant = constant_of_constant(name, entry)
            end

            table[name.name] = constant
          end
        end

        def children(name)
          children_table[name]
        end

        def constant(name)
          constants_table[name]
        end

        def constant_of_module(name, entry)
          type = Types::ClassSingleton.new(
            name: name,
            location: nil
          )

          Constant.new(name: name, type: type, entry: entry)
        end

        def constant_of_constant(name, entry)
          Constant.new(name: name, type: entry.decl.type, entry: entry)
        end
      end

      attr_reader :builder, :table
      attr_reader :context_constants_cache, :child_constants_cache

      def initialize(builder:)
        @builder = builder
        @table = Table.new(builder.env)
        @context_constants_cache = {}
        @child_constants_cache = {}
      end

      def resolve(name, context:)
        cs = constants(context) or raise "Broken context is given"
        cs[name]
      end

      def constants(context)
        unless context_constants_cache.key?(context)
          load_context_constants(context)
        end

        context_constants_cache[context]
      end

      def resolve_child(module_name, name)
        children(module_name)[name]
      end

      def children(module_name)
        unless child_constants_cache.key?(module_name)
          load_child_constants(module_name)
        end

        child_constants_cache[module_name] or raise
      end

      def load_context_constants(context)
        # @type var consts: Hash[Symbol, Constant]
        consts = {}

        if last = context&.[](1)
          constants_from_ancestors(last, constants: consts)
        else
          constants_from_ancestors(BuiltinNames::Object.name, constants: consts)
        end
        constants_from_context(context, constants: consts) or return
        constants_itself(context, constants: consts)

        context_constants_cache[context] = consts
      end

      def load_child_constants(name)
        # @type var constants: Hash[Symbol, Constant]
        constants = {}

        if table.children(name)
          builder.ancestor_builder.instance_ancestors(name).ancestors.reverse_each do |ancestor|
            if ancestor.is_a?(Definition::Ancestor::Instance)
              if ancestor.name == BuiltinNames::Object.name
                if name != BuiltinNames::Object.name
                  next
                end
              end

              case ancestor.source
              when AST::Members::Include, :super, nil
                consts = table.children(ancestor.name) or raise
                constants.merge!(consts)
              end
            end
          end
        end

        child_constants_cache[name] = constants
      end

      def constants_from_context(context, constants:)
        if context
          parent, last = context

          constants_from_context(parent, constants: constants) or return false

          if last
            consts = table.children(last) or return false
            constants.merge!(consts)
          end
        end

        true
      end

      def constants_from_ancestors(module_name, constants:)
        entry = builder.env.class_decls[module_name]

        if entry.is_a?(Environment::ModuleEntry)
          constants.merge!(table.children(BuiltinNames::Object.name) || raise)
          constants.merge!(table.toplevel)
        end

        builder.ancestor_builder.instance_ancestors(module_name).ancestors.reverse_each do |ancestor|
          if ancestor.is_a?(Definition::Ancestor::Instance)
            case ancestor.source
            when AST::Members::Include, :super, nil
              consts = table.children(ancestor.name) or raise
              if ancestor.name == BuiltinNames::Object.name && entry.is_a?(Environment::ClassEntry)
                # Insert toplevel constants as ::Object's constants
                consts.merge!(table.toplevel)
              end
              constants.merge!(consts)
            end
          end
        end
      end

      def constants_itself(context, constants:)
        if context
          _, typename = context

          if typename
            if (ns = typename.namespace).empty?
              constant = table.toplevel[typename.name] or raise
            else
              hash = table.children(ns.to_type_name) or raise
              constant = hash[typename.name]
            end

            constants[typename.name] = constant
          end
        end
      end
    end
  end
end
