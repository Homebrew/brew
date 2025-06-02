# frozen_string_literal: true

module RBS
  class DefinitionBuilder
    attr_reader :env
    attr_reader :type_name_resolver
    attr_reader :ancestor_builder
    attr_reader :method_builder

    attr_reader :instance_cache
    attr_reader :singleton_cache
    attr_reader :singleton0_cache
    attr_reader :interface_cache

    def initialize(env:, ancestor_builder: nil, method_builder: nil)
      @env = env
      @type_name_resolver = TypeNameResolver.from_env(env)
      @ancestor_builder = ancestor_builder || AncestorBuilder.new(env: env)
      @method_builder = method_builder || MethodBuilder.new(env: env)

      @instance_cache = {}
      @singleton_cache = {}
      @singleton0_cache = {}
      @interface_cache = {}
    end

    def ensure_namespace!(namespace, location:)
      namespace.ascend do |ns|
        unless ns.empty?
          NoTypeFoundError.check!(ns.to_type_name, env: env, location: location)
        end
      end
    end

    def build_interface(type_name)
      try_cache(type_name, cache: interface_cache) do
        entry = env.interface_decls[type_name] or raise "Unknown name for build_interface: #{type_name}"
        declaration = entry.decl
        ensure_namespace!(type_name.namespace, location: declaration.location)

        self_type = Types::Interface.new(
          name: type_name,
          args: Types::Variable.build(declaration.type_params.each.map(&:name)),
          location: nil
        )

        ancestors = ancestor_builder.interface_ancestors(type_name)
        Definition.new(type_name: type_name, entry: entry, self_type: self_type, ancestors: ancestors).tap do |definition|
          included_interfaces = ancestor_builder.one_interface_ancestors(type_name).included_interfaces or raise
          included_interfaces.each do |mod|
            defn = build_interface(mod.name)
            subst = Substitution.build(defn.type_params, mod.args)

            defn.methods.each do |name, method|
              definition.methods[name] = method.sub(subst)
            end
          end

          methods = method_builder.build_interface(type_name)
          one_ancestors = ancestor_builder.one_interface_ancestors(type_name)

          validate_type_params(definition, methods: methods, ancestors: one_ancestors)

          methods.each do |defn|
            method = case original = defn.original
                     when AST::Members::MethodDefinition
                       defs = original.types.map do |method_type|
                         Definition::Method::TypeDef.new(
                           type: method_type,
                           member: original,
                           defined_in: type_name,
                           implemented_in: nil
                         )
                       end

                       Definition::Method.new(
                         super_method: nil,
                         defs: defs,
                         accessibility: :public,
                         alias_of: nil
                       )
                     when AST::Members::Alias
                       unless definition.methods.key?(original.old_name)
                         raise UnknownMethodAliasError.new(
                           type_name: type_name,
                           original_name: original.old_name,
                           aliased_name: original.new_name,
                           location: original.location
                         )
                       end

                       original_method = definition.methods[original.old_name]
                       Definition::Method.new(
                         super_method: nil,
                         defs: original_method.defs.map do |defn|
                           defn.update(implemented_in: nil, defined_in: type_name)
                         end,
                         accessibility: :public,
                         alias_of: original_method
                       )
                     when nil
                       unless definition.methods.key?(defn.name)
                         raise InvalidOverloadMethodError.new(
                           type_name: type_name,
                           method_name: defn.name,
                           kind: :instance,
                           members: defn.overloads
                         )
                       end

                       definition.methods[defn.name]

                     when AST::Members::AttrReader, AST::Members::AttrWriter, AST::Members::AttrAccessor
                       raise

                     end

            defn.overloads.each do |overload|
              overload_defs = overload.types.map do |method_type|
                Definition::Method::TypeDef.new(
                  type: method_type,
                  member: overload,
                  defined_in: type_name,
                  implemented_in: nil
                )
              end

              method.defs.unshift(*overload_defs)
            end

            definition.methods[defn.name] = method
          end
        end
      end
    end

    def build_instance(type_name, no_self_types: false)
      try_cache(type_name, cache: instance_cache, key: [type_name, no_self_types]) do
        entry = env.class_decls[type_name] or raise "Unknown name for build_instance: #{type_name}"
        ensure_namespace!(type_name.namespace, location: entry.decls[0].decl.location)

        case entry
        when Environment::ClassEntry, Environment::ModuleEntry
          ancestors = ancestor_builder.instance_ancestors(type_name)
          args = entry.type_params.map {|param| Types::Variable.new(name: param.name, location: param.location) }
          self_type = Types::ClassInstance.new(name: type_name, args: args, location: nil)

          Definition.new(type_name: type_name, entry: entry, self_type: self_type, ancestors: ancestors).tap do |definition|
            one_ancestors = ancestor_builder.one_instance_ancestors(type_name)
            methods = method_builder.build_instance(type_name)

            validate_type_params definition, methods: methods, ancestors: one_ancestors

            if super_class = one_ancestors.super_class
              case super_class
              when Definition::Ancestor::Instance
                build_instance(super_class.name).yield_self do |defn|
                  merge_definition(src: defn,
                                  dest: definition,
                                  subst: Substitution.build(defn.type_params, super_class.args),
                                  keep_super: true)
                end
              else
                raise
              end
            end

            if self_types = one_ancestors.self_types
              unless no_self_types
                self_types.each do |ans|
                  defn = if ans.name.interface?
                           build_interface(ans.name)
                         else
                           build_instance(ans.name)
                         end

                  # Successor interface method overwrites.
                  merge_definition(
                    src: defn,
                    dest: definition,
                    subst: Substitution.build(defn.type_params, ans.args),
                    keep_super: true
                  )
                end
              else
                methods_with_self = build_instance(type_name, no_self_types: false).methods
              end
            end

            one_ancestors.each_included_module do |mod|
              defn = build_instance(mod.name, no_self_types: true)
              merge_definition(src: defn,
                               dest: definition,
                               subst: Substitution.build(defn.type_params, mod.args))
            end

            interface_methods = {}

            one_ancestors.each_included_interface do |mod|
              defn = build_interface(mod.name)
              subst = Substitution.build(defn.type_params, mod.args)

              defn.methods.each do |name, method|
                if interface_methods.key?(name)
                  include_member = mod.source

                  raise unless include_member.is_a?(AST::Members::Include)

                  raise DuplicatedInterfaceMethodDefinitionError.new(
                    type: self_type,
                    method_name: name,
                    member: include_member
                  )
                end

                merge_method(type_name, interface_methods, name, method, subst, implemented_in: type_name)
              end
            end

            if entry.is_a?(Environment::ModuleEntry)
              define_methods_module_instance(
                definition,
                methods: methods,
                interface_methods: interface_methods,
                module_self_methods: methods_with_self
              )
            else
              define_methods_instance(definition, methods: methods, interface_methods: interface_methods)
            end

            entry.decls.each do |d|
              subst = Substitution.build(d.decl.type_params.each.map(&:name), args)

              d.decl.members.each do |member|
                case member
                when AST::Members::AttrReader, AST::Members::AttrAccessor, AST::Members::AttrWriter
                  if member.kind == :instance
                    ivar_name = case member.ivar_name
                                when false
                                  nil
                                else
                                  member.ivar_name || :"@#{member.name}"
                                end

                    if ivar_name
                      insert_variable(type_name,
                                      definition.instance_variables,
                                      name: ivar_name,
                                      type: member.type.sub(subst))
                    end
                  end

                when AST::Members::InstanceVariable
                  insert_variable(type_name,
                                  definition.instance_variables,
                                  name: member.name,
                                  type: member.type.sub(subst))

                when AST::Members::ClassVariable
                  insert_variable(type_name, definition.class_variables, name: member.name, type: member.type)
                end
              end
            end

            one_ancestors.each_prepended_module do |mod|
              defn = build_instance(mod.name)
              merge_definition(src: defn,
                               dest: definition,
                               subst: Substitution.build(defn.type_params, mod.args))
            end
          end
        end
      end
    end

    # Builds a definition for singleton without .new method.
    #
    def build_singleton0(type_name)
      try_cache type_name, cache: singleton0_cache do
        entry = env.class_decls[type_name] or raise "Unknown name for build_singleton0: #{type_name}"
        ensure_namespace!(type_name.namespace, location: entry.decls[0].decl.location)

        case entry
        when Environment::ClassEntry, Environment::ModuleEntry
          ancestors = ancestor_builder.singleton_ancestors(type_name)
          self_type = Types::ClassSingleton.new(name: type_name, location: nil)

          Definition.new(type_name: type_name, entry: entry, self_type: self_type, ancestors: ancestors).tap do |definition|
            one_ancestors = ancestor_builder.one_singleton_ancestors(type_name)

            if super_class = one_ancestors.super_class
              case super_class
              when Definition::Ancestor::Instance
                defn = build_instance(super_class.name)
                merge_definition(src: defn,
                                 dest: definition,
                                 subst: Substitution.build(defn.type_params, super_class.args),
                                 keep_super: true)
              when Definition::Ancestor::Singleton
                defn = build_singleton0(super_class.name)
                merge_definition(src: defn, dest: definition, subst: Substitution.new, keep_super: true)
              end
            end

            one_ancestors.each_extended_module do |mod|
              mod.args.each do |arg|
                validate_type_presence(arg)
              end

              mod_defn = build_instance(mod.name, no_self_types: true)
              merge_definition(src: mod_defn,
                               dest: definition,
                               subst: Substitution.build(mod_defn.type_params, mod.args))
            end

            interface_methods = {}
            one_ancestors.each_extended_interface do |mod|
              mod.args.each do |arg|
                validate_type_presence(arg)
              end

              mod_defn = build_interface(mod.name)
              subst = Substitution.build(mod_defn.type_params, mod.args)

              mod_defn.methods.each do |name, method|
                if interface_methods.key?(name)
                  src_member = mod.source

                  raise unless src_member.is_a?(AST::Members::Extend)

                  raise DuplicatedInterfaceMethodDefinitionError.new(
                    type: self_type,
                    method_name: name,
                    member: src_member
                  )
                end

                merge_method(type_name, interface_methods, name, method, subst, implemented_in: type_name)
              end
            end

            methods = method_builder.build_singleton(type_name)
            define_methods_singleton(definition, methods: methods, interface_methods: interface_methods)

            entry.decls.each do |d|
              d.decl.members.each do |member|
                case member
                when AST::Members::AttrReader, AST::Members::AttrAccessor, AST::Members::AttrWriter
                  if member.kind == :singleton
                    ivar_name = case member.ivar_name
                                when false
                                  nil
                                else
                                  member.ivar_name || :"@#{member.name}"
                                end

                    if ivar_name
                      insert_variable(type_name, definition.instance_variables, name: ivar_name, type: member.type)
                    end
                  end

                when AST::Members::ClassInstanceVariable
                  insert_variable(type_name, definition.instance_variables, name: member.name, type: member.type)

                when AST::Members::ClassVariable
                  insert_variable(type_name, definition.class_variables, name: member.name, type: member.type)
                end
              end
            end
          end
        end
      end
    end

    def build_singleton(type_name)
      try_cache type_name, cache: singleton_cache do
        entry = env.class_decls[type_name] or raise "Unknown name for build_singleton: #{type_name}"
        ensure_namespace!(type_name.namespace, location: entry.decls[0].decl.location)

        case entry
        when Environment::ClassEntry, Environment::ModuleEntry
          ancestors = ancestor_builder.singleton_ancestors(type_name)
          self_type = Types::ClassSingleton.new(name: type_name, location: nil)

          Definition.new(type_name: type_name, entry: entry, self_type: self_type, ancestors: ancestors).tap do |definition|
            def0 = build_singleton0(type_name)
            subst = Substitution.new

            merge_definition(src: def0, dest: definition, subst: subst, keep_super: true)

            if entry.is_a?(Environment::ClassEntry)
              new_method = definition.methods[:new]
              if new_method.defs.all? {|d| d.defined_in == BuiltinNames::Class.name }
                alias_methods = definition.methods.each.with_object([]) do |entry, array|
                  # @type var method: Definition::Method?
                  name, method = entry
                  while method
                    if method.alias_of == new_method
                      array << name
                      break
                    end
                    method = method.alias_of
                  end
                end

                # The method is _untyped new_.

                instance = build_instance(type_name)
                initialize = instance.methods[:initialize]

                if initialize
                  class_params = entry.type_params

                  # Inject a virtual _typed new_.
                  initialize_defs = initialize.defs
                  typed_new = Definition::Method.new(
                    super_method: new_method,
                    defs: initialize_defs.map do |initialize_def|
                      method_type = initialize_def.type

                      class_type_param_vars = Set.new(class_params.map(&:name))
                      method_type_param_vars = Set.new(method_type.type_params.map(&:name))

                      if class_type_param_vars.intersect?(method_type_param_vars)
                        new_method_param_names = method_type.type_params.map do |method_param|
                          if class_type_param_vars.include?(method_param.name)
                            Types::Variable.fresh(method_param.name).name
                          else
                            method_param.name
                          end
                        end

                        sub = Substitution.build(
                          method_type.type_params.map(&:name),
                          Types::Variable.build(new_method_param_names)
                        )

                        method_params = class_params + AST::TypeParam.rename(method_type.type_params, new_names: new_method_param_names)
                        method_type = method_type
                          .update(type_params: [])
                          .sub(sub)
                          .update(type_params: method_params)
                      else
                        method_type = method_type
                          .update(type_params: class_params + method_type.type_params)
                      end

                      method_type = method_type.update(
                        type: method_type.type.with_return_type(
                          Types::ClassInstance.new(
                            name: type_name,
                            args: entry.type_params.map {|param| Types::Variable.new(name: param.name, location: param.location) },
                            location: nil
                          )
                        )
                      )

                      Definition::Method::TypeDef.new(
                        type: method_type,
                        member: initialize_def.member,
                        defined_in: initialize_def.defined_in,
                        implemented_in: initialize_def.implemented_in
                      )
                    end,
                    accessibility: :public,
                    annotations: [],
                    alias_of: nil
                  )

                  definition.methods[:new] = typed_new

                  alias_methods.each do |alias_name|
                    definition.methods[alias_name] = definition.methods[alias_name].update(
                      alias_of: typed_new,
                      defs: typed_new.defs
                    )
                  end
                end
              end
            end
          end
        end
      end
    end

    def validate_params_with(type_params, result:)
      type_params.each do |param|
        unless param.unchecked?
          unless result.compatible?(param.name, with_annotation: param.variance)
            yield param
          end
        end
      end
    end

    def source_location(source, decl)
      case source
      when nil
        decl.location
      when :super
        case decl
        when AST::Declarations::Class
          decl.super_class&.location
        end
      else
        source.location
      end
    end

    def validate_type_params(definition, ancestors:, methods:)
      type_params = definition.type_params_decl

      calculator = VarianceCalculator.new(builder: self)
      param_names = type_params.each.map(&:name)

      ancestors.each_ancestor do |ancestor|
        case ancestor
        when Definition::Ancestor::Instance
          result = calculator.in_inherit(name: ancestor.name, args: ancestor.args, variables: param_names)
          validate_params_with(type_params, result: result) do |param|
            decl = case entry = definition.entry
                   when Environment::ModuleEntry, Environment::ClassEntry
                     entry.primary.decl
                   when Environment::SingleEntry
                     entry.decl
                   end

            raise InvalidVarianceAnnotationError.new(
              type_name: definition.type_name,
              param: param,
              location: source_location(ancestor.source, decl)
            )
          end
        end
      end

      methods.each do |defn|
        next if defn.name == :initialize

        method_types = case original = defn.original
                       when AST::Members::MethodDefinition
                         original.types
                       when AST::Members::AttrWriter, AST::Members::AttrReader, AST::Members::AttrAccessor
                         if defn.name.to_s.end_with?("=")
                           [
                             MethodType.new(
                               type_params: [],
                               type: Types::Function.empty(original.type).update(
                                 required_positionals: [
                                   Types::Function::Param.new(type: original.type, name: original.name)
                                 ]
                               ),
                               block: nil,
                               location: original.location
                             )
                           ]
                         else
                           [
                             MethodType.new(
                               type_params: [],
                               type: Types::Function.empty(original.type),
                               block: nil,
                               location: original.location
                             )
                           ]
                         end
                       when AST::Members::Alias
                         nil
                       when nil
                         nil
                       end

        if method_types
          method_types.each do |method_type|
            merged_params = type_params
              .reject {|param| method_type.type_param_names.include?(param.name) }
              .concat(method_type.type_params)

            result = calculator.in_method_type(method_type: method_type, variables: param_names)
            validate_params_with(merged_params, result: result) do |param|
              raise InvalidVarianceAnnotationError.new(
                type_name: definition.type_name,
                param: param,
                location: method_type.location
              )
            end
          end
        end
      end
    end

    def insert_variable(type_name, variables, name:, type:)
      variables[name] = Definition::Variable.new(
        parent_variable: variables[name],
        type: type,
        declared_in: type_name
      )
    end

    def define_methods_instance(definition, methods:, interface_methods:)
      define_methods(
        definition,
        methods: methods,
        interface_methods: interface_methods,
        methods_with_self: nil,
        super_interface_method: false
      )
    end

    def define_methods_module_instance(definition, methods:, interface_methods:, module_self_methods:)
      define_methods(definition, methods: methods, interface_methods: interface_methods, methods_with_self: module_self_methods, super_interface_method: true)
    end

    def define_methods_singleton(definition, methods:, interface_methods:)
      define_methods(
        definition,
        methods: methods,
        interface_methods: interface_methods,
        methods_with_self: nil,
        super_interface_method: false
      )
    end

    def define_methods(definition, methods:, interface_methods:, methods_with_self:, super_interface_method:)
      methods.each do |method_def|
        method_name = method_def.name
        original = method_def.original

        if original.is_a?(AST::Members::Alias)
          existing_method = interface_methods[method_name] || definition.methods[method_name]
          original_method =
            interface_methods[original.old_name] ||
            methods_with_self&.[](original.old_name) ||
            definition.methods[original.old_name]

          unless original_method
            raise UnknownMethodAliasError.new(
              type_name: definition.type_name,
              original_name: original.old_name,
              aliased_name: original.new_name,
              location: original.location
            )
          end

          method = Definition::Method.new(
            super_method: existing_method,
            defs: original_method.defs.map do |defn|
              defn.update(defined_in: definition.type_name, implemented_in: definition.type_name)
            end,
            accessibility: original_method.accessibility,
            alias_of: original_method
          )
        else
          if interface_methods.key?(method_name)
            interface_method = interface_methods[method_name]

            if original = method_def.original
              raise DuplicatedMethodDefinitionError.new(
                type: definition.self_type,
                method_name: method_name,
                members: [original]
              )
            end

            definition.methods[method_name] = interface_method
          end

          existing_method = definition.methods[method_name]

          case original
          when AST::Members::MethodDefinition
            defs = original.types.map do |method_type|
              Definition::Method::TypeDef.new(
                type: method_type,
                member: original,
                defined_in: definition.type_name,
                implemented_in: definition.type_name
              )
            end

            # @type var accessibility: RBS::Definition::accessibility
            accessibility = if method_name == :initialize
                              :private
                            else
                              method_def.accessibility
                            end

            method = Definition::Method.new(
              super_method: existing_method,
              defs: defs,
              accessibility: accessibility,
              alias_of: nil
            )

          when AST::Members::AttrReader, AST::Members::AttrWriter, AST::Members::AttrAccessor
            method_type = if method_name.to_s.end_with?("=")
                            # setter
                            MethodType.new(
                              type_params: [],
                              type: Types::Function.empty(original.type).update(
                                required_positionals: [
                                  Types::Function::Param.new(type: original.type, name: original.name)
                                ]
                              ),
                              block: nil,
                              location: nil
                            )
                          else
                            # getter
                            MethodType.new(
                              type_params: [],
                              type: Types::Function.empty(original.type),
                              block: nil,
                              location: nil
                            )
                          end
            defs = [
              Definition::Method::TypeDef.new(
                type: method_type,
                member: original,
                defined_in: definition.type_name,
                implemented_in: definition.type_name
              )
            ]

            method = Definition::Method.new(
              super_method: existing_method,
              defs: defs,
              accessibility: method_def.accessibility,
              alias_of: nil
            )

          when nil
            unless definition.methods.key?(method_name)
              raise InvalidOverloadMethodError.new(
                type_name: definition.type_name,
                method_name: method_name,
                kind: :instance,
                members: method_def.overloads
              )
            end

            if !super_interface_method && existing_method.defs.any? {|defn| defn.defined_in.interface? }
              super_method = existing_method.super_method
            else
              super_method = existing_method
            end

            method = Definition::Method.new(
              super_method: super_method,
              defs: existing_method.defs.map do |defn|
                defn.update(implemented_in: definition.type_name)
              end,
              accessibility: existing_method.accessibility,
              alias_of: existing_method.alias_of
            )
          end
        end

        method_def.overloads.each do |overload|
          type_defs = overload.types.map do |method_type|
            Definition::Method::TypeDef.new(
              type: method_type,
              member: overload,
              defined_in: definition.type_name,
              implemented_in: definition.type_name
            )
          end

          method.defs.unshift(*type_defs)
        end

        definition.methods[method_name] = method
      end

      interface_methods.each do |name, method|
        unless methods.methods.key?(name)
          merge_method(definition.type_name, definition.methods, name, method, Substitution.new)
        end
      end
    end

    def merge_definition(src:, dest:, subst:, implemented_in: :keep, keep_super: false)
      src.methods.each do |name, method|
        merge_method(dest.type_name, dest.methods, name, method, subst, implemented_in: implemented_in, keep_super: keep_super)
      end

      src.instance_variables.each do |name, variable|
        merge_variable(dest.instance_variables, name, variable, subst, keep_super: keep_super)
      end

      src.class_variables.each do |name, variable|
        merge_variable(dest.class_variables, name, variable, subst, keep_super: keep_super)
      end
    end

    def merge_variable(variables, name, variable, sub, keep_super: false)
      super_variable = variables[name]

      variables[name] = Definition::Variable.new(
        parent_variable: keep_super ? variable.parent_variable : super_variable,
        type: sub.empty? ? variable.type : variable.type.sub(sub),
        declared_in: variable.declared_in
      )
    end

    def merge_method(type_name, methods, name, method, sub, implemented_in: :keep, keep_super: false)
      if sub.empty? && implemented_in == :keep && keep_super
        methods[name] = method
      else
        if sub.empty? && implemented_in == :keep
          defs = method.defs
        else
          defs = method.defs.map do |defn|
            defn.update(
              type: sub.empty? ? defn.type : defn.type.sub(sub),
              implemented_in: case implemented_in
                              when :keep
                                defn.implemented_in
                              when nil
                                nil
                              else
                                implemented_in
                              end
            )
          end

          defs = method.defs.map do |defn|
            defn.update(
              type: sub.empty? ? defn.type : defn.type.sub(sub),
              implemented_in: case implemented_in
                              when :keep
                                defn.implemented_in
                              when nil
                                nil
                              else
                                implemented_in
                              end
            )
          end
        end

        super_method = methods[name]

        methods[name] = Definition::Method.new(
          super_method: keep_super ? method.super_method : super_method,
          accessibility: method.accessibility,
          defs: defs,
          alias_of: method.alias_of
        )
      end
    end

    def try_cache(type_name, cache:, key: nil)
      # @type var cc: Hash[untyped, Definition | nil]
      # @type var key: untyped
      key ||= type_name
      cc = _ = cache

      cc[key] ||= yield
    end

    def expand_alias(type_name)
      expand_alias2(type_name, [])
    end

    def expand_alias1(type_name)
      entry = env.alias_decls[type_name] or raise "Unknown alias name: #{type_name}"
      as = entry.decl.type_params.each.map { Types::Bases::Any.new(location: nil) }
      expand_alias2(type_name, as)
    end

    def expand_alias2(type_name, args)
      entry = env.alias_decls[type_name] or raise "Unknown alias name: #{type_name}"

      ensure_namespace!(type_name.namespace, location: entry.decl.location)
      params = entry.decl.type_params.each.map(&:name)

      unless params.size == args.size
        as = "[#{args.join(", ")}]" unless args.empty?
        ps = "[#{params.join(", ")}]" unless params.empty?

        raise "Invalid type application: type = #{type_name}#{as}, decl = #{type_name}#{ps}"
      end

      type = entry.decl.type

      unless params.empty?
        subst = Substitution.build(params, args)
        type = type.sub(subst)
      end

      type
    end

    def update(env:, except:, ancestor_builder:)
      method_builder = self.method_builder.update(env: env, except: except)

      DefinitionBuilder.new(env: env, ancestor_builder: ancestor_builder, method_builder: method_builder).tap do |builder|
        builder.instance_cache.merge!(instance_cache)
        builder.singleton_cache.merge!(singleton_cache)
        builder.singleton0_cache.merge!(singleton0_cache)
        builder.interface_cache.merge!(interface_cache)

        except.each do |name|
          builder.instance_cache.delete([name, true])
          builder.instance_cache.delete([name, false])
          builder.singleton_cache.delete(name)
          builder.singleton0_cache.delete(name)
          builder.interface_cache.delete(name)
        end
      end
    end

    def validate_type_presence(type)
      case type
      when Types::ClassInstance, Types::ClassSingleton, Types::Interface, Types::Alias
        validate_type_name(type.name, type.location)
      end

      type.each_type do |type|
        validate_type_presence(type)
      end
    end

    def validate_type_name(name, location)
      name = name.absolute!

      return if name.class? && env.class_decls.key?(name)
      return if name.interface? && env.interface_decls.key?(name)
      return if name.alias? && env.alias_decls.key?(name)

      raise NoTypeFoundError.new(type_name: name, location: location)
    end
  end
end
