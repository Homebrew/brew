# frozen_string_literal: true

module RBS
  class ConstantTable
    attr_reader :definition_builder
    attr_reader :constant_scopes_cache

    def env
      definition_builder.env
    end

    def resolver
      @resolver ||= TypeNameResolver.from_env(env)
    end

    def initialize(builder:)
      @definition_builder = builder
      @constant_scopes_cache = {}
    end

    def absolute_type(type, context:)
      type.map_type_name do |type_name, location|
        absolute_type_name(type_name, context: context, location: location)
      end
    end

    def absolute_type_name(type_name, context:, location:)
      resolver.resolve(type_name, context: context) or
        raise NoTypeFoundError.new(type_name: type_name, location: location)
    end

    def name_to_constant(name)
      case
      when entry = env.constant_decls[name]
        type = absolute_type(entry.decl.type, context: entry.context)
        Constant.new(name: name, type: type, entry: entry)
      when entry = env.class_decls[name]
        type = Types::ClassSingleton.new(name: name, location: nil)
        Constant.new(name: name, type: type, entry: entry)
      end
    end

    def split_name(name)
      name.namespace.path + [name.name]
    end

    def resolve_constant_reference(name, context:)
      raise "Context cannot be empty: Specify `[Namespace.root]`" if context.empty?

      head, *tail = split_name(name)

      raise unless head

      head_constant = case
                      when name.absolute?
                        name_to_constant(TypeName.new(name: head, namespace: Namespace.root))
                      when context == [Namespace.root]
                        name_to_constant(TypeName.new(name: head, namespace: Namespace.root))
                      else
                        resolve_constant_reference_context(head, context: context) ||
                          context.first.yield_self do |first_context|
                            raise unless first_context
                            resolve_constant_reference_inherit(head, scopes: constant_scopes(first_context.to_type_name))
                          end
                      end

      tail.inject(head_constant) do |constant, name|
        if constant
          resolve_constant_reference_inherit(
            name,
            scopes: constant_scopes(constant.name),
            no_object: constant.name != BuiltinNames::Object.name
          )
        end
      end
    end

    def resolve_constant_reference_context(name, context:)
      head, *tail = context

      if head
        if head.path.last == name
          name_to_constant(head.to_type_name)
        else
          name_to_constant(TypeName.new(name: name, namespace: head)) ||
            resolve_constant_reference_context(name, context: tail)
        end
      end
    end

    def resolve_constant_reference_inherit(name, scopes:, no_object: false)
      scopes.each do |context|
        if context.path == [:Object]
          unless no_object
            constant = name_to_constant(TypeName.new(name: name, namespace: context)) ||
              name_to_constant(TypeName.new(name: name, namespace: Namespace.root))
          end
        else
          constant = name_to_constant(TypeName.new(name: name, namespace: context))
        end

        return constant if constant
      end

      nil
    end

    def constant_scopes(name)
      constant_scopes_cache[name] ||= constant_scopes0(name, scopes: [])
    end

    def constant_scopes_module(name, scopes:)
      entry = env.class_decls[name]
      namespace = name.to_namespace

      entry.decls.each do |d|
        d.decl.members.each do |member|
          case member
          when AST::Members::Include
            if member.name.class?
              constant_scopes_module absolute_type_name(member.name, context: d.context, location: member.location),
                                     scopes: scopes
            end
          end
        end
      end

      scopes.unshift namespace
    end

    def constant_scopes0(name, scopes: [])
      entry = env.class_decls[name]
      namespace = name.to_namespace

      case entry
      when Environment::ClassEntry
        unless name == BuiltinNames::BasicObject.name
          super_name = entry.primary.decl.super_class&.yield_self do |super_class|
            absolute_type_name(super_class.name, context: entry.primary.context, location: entry.primary.decl.location)
          end || BuiltinNames::Object.name

          constant_scopes0 super_name, scopes: scopes
        end

        entry.decls.each do |d|
          d.decl.members.each do |member|
            case member
            when AST::Members::Include
              if member.name.class?
                constant_scopes_module absolute_type_name(member.name, context: d.context, location: member.location),
                                       scopes: scopes
              end
            end
          end
        end

        scopes.unshift namespace

      when Environment::ModuleEntry
        constant_scopes0 BuiltinNames::Module.name, scopes: scopes
        constant_scopes_module name, scopes: scopes
      end

      scopes
    end
  end
end
