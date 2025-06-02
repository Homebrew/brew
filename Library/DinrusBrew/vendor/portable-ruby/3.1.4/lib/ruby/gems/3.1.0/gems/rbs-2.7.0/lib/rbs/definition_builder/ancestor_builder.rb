# frozen_string_literal: true

module RBS
  class DefinitionBuilder
    class AncestorBuilder
      class OneAncestors
        attr_reader :type_name
        attr_reader :params
        attr_reader :super_class
        attr_reader :self_types
        attr_reader :included_modules
        attr_reader :included_interfaces
        attr_reader :prepended_modules
        attr_reader :extended_modules
        attr_reader :extended_interfaces

        def initialize(type_name:, params:, super_class:, self_types:, included_modules:, included_interfaces:, prepended_modules:, extended_modules:, extended_interfaces:)
          @type_name = type_name
          @params = params
          @super_class = super_class
          @self_types = self_types
          @included_modules = included_modules
          @included_interfaces = included_interfaces
          @prepended_modules = prepended_modules
          @extended_modules = extended_modules
          @extended_interfaces = extended_interfaces
        end

        def each_ancestor(&block)
          if block
            if s = super_class
              yield s
            end

            each_self_type(&block)
            each_included_module(&block)
            each_included_interface(&block)
            each_prepended_module(&block)
            each_extended_module(&block)
            each_extended_interface(&block)
          else
            enum_for :each_ancestor
          end
        end

        def each_self_type(&block)
          if block
            self_types&.each(&block)
          else
            enum_for :each_self_type
          end
        end

        def each_included_module(&block)
          if block
            included_modules&.each(&block)
          else
            enum_for :each_included_module
          end
        end

        def each_included_interface(&block)
          if block
            included_interfaces&.each(&block)
          else
            enum_for :each_included_interface
          end
        end

        def each_prepended_module(&block)
          if block
            prepended_modules&.each(&block)
          else
            enum_for :each_prepended_module
          end
        end

        def each_extended_module(&block)
          if block
            extended_modules&.each(&block)
          else
            enum_for :each_extended_module
          end
        end

        def each_extended_interface(&block)
          if block
            extended_interfaces&.each(&block)
          else
            enum_for :each_extended_interface
          end
        end

        def self.class_instance(type_name:, params:, super_class:)
          new(
            type_name: type_name,
            params: params,
            super_class: super_class,
            self_types: nil,
            included_modules: [],
            included_interfaces: [],
            prepended_modules: [],
            extended_modules: nil,
            extended_interfaces: nil
          )
        end

        def self.singleton(type_name:, super_class:)
          new(
            type_name: type_name,
            params: nil,
            super_class: super_class,
            self_types: nil,
            included_modules: nil,
            included_interfaces: nil,
            prepended_modules: nil,
            extended_modules: [],
            extended_interfaces: []
          )
        end

        def self.module_instance(type_name:, params:)
          new(
            type_name: type_name,
            params: params,
            self_types: [],
            included_modules: [],
            included_interfaces: [],
            prepended_modules: [],
            super_class: nil,
            extended_modules: nil,
            extended_interfaces: nil
          )
        end

        def self.interface(type_name:, params:)
          new(
            type_name: type_name,
            params: params,
            self_types: nil,
            included_modules: nil,
            included_interfaces: [],
            prepended_modules: nil,
            super_class: nil,
            extended_modules: nil,
            extended_interfaces: nil
          )
        end
      end

      attr_reader :env

      attr_reader :one_instance_ancestors_cache
      attr_reader :instance_ancestors_cache

      attr_reader :one_singleton_ancestors_cache
      attr_reader :singleton_ancestors_cache

      attr_reader :one_interface_ancestors_cache
      attr_reader :interface_ancestors_cache

      def initialize(env:)
        @env = env

        @one_instance_ancestors_cache = {}
        @instance_ancestors_cache = {}

        @one_singleton_ancestors_cache = {}
        @singleton_ancestors_cache = {}

        @one_interface_ancestors_cache = {}
        @interface_ancestors_cache = {}
      end

      def validate_super_class!(type_name, entry)
        with_super_classes = entry.decls.select {|d| d.decl.super_class }

        return if with_super_classes.size <= 1

        super_types = with_super_classes.map do |d|
          super_class = d.decl.super_class or raise
          Types::ClassInstance.new(name: super_class.name, args: super_class.args, location: nil)
        end

        super_types.uniq!

        return if super_types.size == 1

        raise SuperclassMismatchError.new(name: type_name, entry: entry)
      end

      def one_instance_ancestors(type_name)
        as = one_instance_ancestors_cache[type_name] and return as

        entry = env.class_decls[type_name] or raise "Unknown name for one_instance_ancestors: #{type_name}"
        params = entry.type_params.each.map(&:name)

        case entry
        when Environment::ClassEntry
          validate_super_class!(type_name, entry)
          primary = entry.primary
          super_class = primary.decl.super_class

          if type_name != BuiltinNames::BasicObject.name
            if super_class
              super_name = super_class.name
              super_args = super_class.args
            else
              super_name = BuiltinNames::Object.name
              super_args = []
            end

            NoSuperclassFoundError.check!(super_name, env: env, location: primary.decl.location)

            ancestors = OneAncestors.class_instance(
              type_name: type_name,
              params: params,
              super_class: Definition::Ancestor::Instance.new(name: super_name, args: super_args, source: :super)
            )
          else
            ancestors = OneAncestors.class_instance(
              type_name: type_name,
              params: params,
              super_class: nil
            )
          end
        when Environment::ModuleEntry
          ancestors = OneAncestors.module_instance(type_name: type_name, params: params)

          self_types = ancestors.self_types or raise
          if entry.self_types.empty?
            self_types.push Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: [], source: nil)
          else
            entry.self_types.each do |module_self|
              NoSelfTypeFoundError.check!(module_self, env: env)
              self_types.push Definition::Ancestor::Instance.new(name: module_self.name, args: module_self.args, source: module_self)
            end
          end
        end

        mixin_ancestors(entry,
                        type_name,
                        included_modules: ancestors.included_modules,
                        included_interfaces: ancestors.included_interfaces,
                        prepended_modules: ancestors.prepended_modules,
                        extended_modules: nil,
                        extended_interfaces: nil)

        one_instance_ancestors_cache[type_name] = ancestors
      end

      def one_singleton_ancestors(type_name)
        as = one_singleton_ancestors_cache[type_name] and return as

        entry = env.class_decls[type_name] or raise "Unknown name for one_singleton_ancestors: #{type_name}"

        case entry
        when Environment::ClassEntry
          validate_super_class!(type_name, entry)
          primary = entry.primary
          super_class = primary.decl.super_class

          if type_name != BuiltinNames::BasicObject.name
            if super_class
              super_name = super_class.name
            else
              super_name = BuiltinNames::Object.name
            end

            NoSuperclassFoundError.check!(super_name, env: env, location: primary.decl.location)

            ancestors = OneAncestors.singleton(
              type_name: type_name,
              super_class: Definition::Ancestor::Singleton.new(name: super_name)
            )
          else
            ancestors = OneAncestors.singleton(
              type_name: type_name,
              super_class: Definition::Ancestor::Instance.new(name: BuiltinNames::Class.name, args: [], source: :super)
            )
          end
        when Environment::ModuleEntry
          ancestors = OneAncestors.singleton(
            type_name: type_name,
            super_class: Definition::Ancestor::Instance.new(name: BuiltinNames::Module.name, args: [], source: :super)
          )
        end

        mixin_ancestors(entry,
                        type_name,
                        included_modules: nil,
                        included_interfaces: nil,
                        prepended_modules: nil,
                        extended_modules: ancestors.extended_modules,
                        extended_interfaces: ancestors.extended_interfaces)

        one_singleton_ancestors_cache[type_name] = ancestors
      end

      def one_interface_ancestors(type_name)
        one_interface_ancestors_cache[type_name] ||=
          begin
            entry = env.interface_decls[type_name] or raise "Unknown name for one_interface_ancestors: #{type_name}"
            params = entry.decl.type_params.each.map(&:name)

            OneAncestors.interface(type_name: type_name, params: params).tap do |ancestors|
              mixin_ancestors0(entry.decl,
                               type_name,
                               align_params: nil,
                               included_modules: nil,
                               included_interfaces: ancestors.included_interfaces,
                               prepended_modules: nil,
                               extended_modules: nil,
                               extended_interfaces: nil)
            end
          end
      end

      def mixin_ancestors0(decl, type_name, align_params:, included_modules:, included_interfaces:, extended_modules:, prepended_modules:, extended_interfaces:)
        decl.each_mixin do |member|
          case member
          when AST::Members::Include
            module_name = member.name
            module_args = member.args.map {|type| align_params ? type.sub(align_params) : type }
            ancestor = Definition::Ancestor::Instance.new(name: module_name, args: module_args, source: member)

            case
            when member.name.class? && included_modules
              MixinClassError.check!(type_name: type_name, env: env, member: member)
              NoMixinFoundError.check!(member.name, env: env, member: member)
              included_modules << ancestor
            when member.name.interface? && included_interfaces
              NoMixinFoundError.check!(member.name, env: env, member: member)
              included_interfaces << ancestor
            end

          when AST::Members::Prepend
            if prepended_modules
              MixinClassError.check!(type_name: type_name, env: env, member: member)
              NoMixinFoundError.check!(member.name, env: env, member: member)

              module_name = member.name
              module_args = member.args.map {|type| align_params ? type.sub(align_params) : type }

              prepended_modules << Definition::Ancestor::Instance.new(name: module_name, args: module_args, source: member)
            end

          when AST::Members::Extend
            module_name = member.name
            module_args = member.args
            ancestor = Definition::Ancestor::Instance.new(name: module_name, args: module_args, source: member)

            case
            when member.name.class? && extended_modules
              MixinClassError.check!(type_name: type_name, env: env, member: member)
              NoMixinFoundError.check!(member.name, env: env, member: member)
              extended_modules << ancestor
            when member.name.interface? && extended_interfaces
              NoMixinFoundError.check!(member.name, env: env, member: member)
              extended_interfaces << ancestor
            end
          end
        end
      end

      def mixin_ancestors(entry, type_name, included_modules:, included_interfaces:, extended_modules:, prepended_modules:, extended_interfaces:)
        entry.decls.each do |d|
          decl = d.decl

          align_params = Substitution.build(
            decl.type_params.each.map(&:name),
            entry.type_params.map {|param| Types::Variable.new(name: param.name, location: param.location) }
          )

          mixin_ancestors0(decl,
                           type_name,
                           align_params: align_params,
                           included_modules: included_modules,
                           included_interfaces: included_interfaces,
                           extended_modules: extended_modules,
                           prepended_modules: prepended_modules,
                           extended_interfaces: extended_interfaces)
        end
      end

      def instance_ancestors(type_name, building_ancestors: [])
        as = instance_ancestors_cache[type_name] and return as

        entry = env.class_decls[type_name] or raise "Unknown name for instance_ancestors: #{type_name}"
        params = entry.type_params.each.map(&:name)
        args = entry.type_params.map do |type_param|
          Types::Variable.new(name: type_param.name, location: type_param.location)
        end
        self_ancestor = Definition::Ancestor::Instance.new(name: type_name, args: args, source: nil)

        RecursiveAncestorError.check!(self_ancestor,
                                      ancestors: building_ancestors,
                                      location: entry.primary.decl.location)
        building_ancestors.push self_ancestor

        one_ancestors = one_instance_ancestors(type_name)

        # @type var ancestors: Array[::RBS::Definition::Ancestor::t]
        ancestors = []

        case entry
        when Environment::ClassEntry
          if super_class = one_ancestors.super_class
            # @type var super_class: Definition::Ancestor::Instance
            super_name = super_class.name
            super_args = super_class.args

            super_ancestors = instance_ancestors(super_name, building_ancestors: building_ancestors)
            ancestors.unshift(*super_ancestors.apply(super_args, location: entry.primary.decl.location))
          end
        end

        if self_types = one_ancestors.self_types
          self_types.each do |mod|
            if mod.name.class?
              # Ensure there is no loop in ancestors chain
              instance_ancestors(mod.name, building_ancestors: building_ancestors)
            end
          end
        end

        if included_modules = one_ancestors.included_modules
          included_modules.each do |mod|
            name = mod.name
            arg_types = mod.args
            mod_ancestors = instance_ancestors(name, building_ancestors: building_ancestors)
            ancestors.unshift(*mod_ancestors.apply(arg_types, location: entry.primary.decl.location))
          end
        end

        ancestors.unshift(self_ancestor)

        if prepended_modules = one_ancestors.prepended_modules
          prepended_modules.each do |mod|
            name = mod.name
            arg_types = mod.args
            mod_ancestors = instance_ancestors(name, building_ancestors: building_ancestors)
            ancestors.unshift(*mod_ancestors.apply(arg_types, location: entry.primary.decl.location))
          end
        end

        building_ancestors.pop

        instance_ancestors_cache[type_name] = Definition::InstanceAncestors.new(
          type_name: type_name,
          params: params,
          ancestors: ancestors
        )
      end

      def singleton_ancestors(type_name, building_ancestors: [])
        as = singleton_ancestors_cache[type_name] and return as

        entry = env.class_decls[type_name] or raise "Unknown name for singleton_ancestors: #{type_name}"
        self_ancestor = Definition::Ancestor::Singleton.new(name: type_name)

        RecursiveAncestorError.check!(self_ancestor,
                                      ancestors: building_ancestors,
                                      location: entry.primary.decl.location)
        building_ancestors.push self_ancestor

        one_ancestors = one_singleton_ancestors(type_name)

        ancestors = []

        case super_class = one_ancestors.super_class
        when Definition::Ancestor::Instance
          super_name = super_class.name
          super_args = super_class.args

          super_ancestors = instance_ancestors(super_name, building_ancestors: building_ancestors)
          ancestors.unshift(*super_ancestors.apply(super_args, location: entry.primary.decl.location))

        when Definition::Ancestor::Singleton
          super_name = super_class.name

          super_ancestors = singleton_ancestors(super_name, building_ancestors: [])
          ancestors.unshift(*super_ancestors.ancestors)
        end

        extended_modules = one_ancestors.extended_modules or raise
        extended_modules.each do |mod|
          name = mod.name
          args = mod.args
          mod_ancestors = instance_ancestors(name, building_ancestors: building_ancestors)
          ancestors.unshift(*mod_ancestors.apply(args, location: entry.primary.decl.location))
        end

        ancestors.unshift(self_ancestor)

        building_ancestors.pop

        singleton_ancestors_cache[type_name] = Definition::SingletonAncestors.new(
          type_name: type_name,
          ancestors: ancestors
        )
      end

      def interface_ancestors(type_name, building_ancestors: [])
        as = interface_ancestors_cache[type_name] and return as

        entry = env.interface_decls[type_name] or raise "Unknown name for interface_ancestors: #{type_name}"
        params = entry.decl.type_params.each.map(&:name)
        args = Types::Variable.build(params)
        self_ancestor = Definition::Ancestor::Instance.new(name: type_name, args: args, source: nil)

        RecursiveAncestorError.check!(self_ancestor,
                                      ancestors: building_ancestors,
                                      location: entry.decl.location)
        building_ancestors.push self_ancestor

        one_ancestors = one_interface_ancestors(type_name)
        ancestors = []

        included_interfaces = one_ancestors.included_interfaces or raise
        included_interfaces.each do |a|
          included_ancestors = interface_ancestors(a.name, building_ancestors: building_ancestors)

          ancestors.unshift(*included_ancestors.apply(a.args, location: entry.decl.location))
        end

        ancestors.unshift(self_ancestor)
        building_ancestors.pop

        interface_ancestors_cache[type_name] = Definition::InstanceAncestors.new(
          type_name: type_name,
          params: params,
          ancestors: ancestors
        )
      end
    end
  end
end
