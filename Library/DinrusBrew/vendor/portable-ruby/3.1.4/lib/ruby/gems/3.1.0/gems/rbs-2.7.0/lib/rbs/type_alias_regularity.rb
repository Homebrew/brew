# frozen_string_literal: true

module RBS
  class TypeAliasRegularity
    class Diagnostic
      attr_reader :type_name, :nonregular_type

      def initialize(type_name:, nonregular_type:)
        @type_name = type_name
        @nonregular_type = nonregular_type
      end
    end

    attr_reader :env, :builder, :diagnostics

    def initialize(env:)
      @env = env
      @builder = DefinitionBuilder.new(env: env)
      @diagnostics = {}
    end

    def validate
      diagnostics.clear

      each_mutual_alias_defs do |names|
        # Find the first generic type alias in strongly connected component.
        # This is to skip the regularity check when the alias is not generic.
        names.each do |name|
          # @type break: nil
          if type = build_alias_type(name)
            # Running validation only once from the first generic type is enough, because they are mutual recursive definition.
            validate_alias_type(type, names, {})
            break
          end
        end
      end
    end

    def validate_alias_type(alias_type, names, types)
      if names.include?(alias_type.name)
        if ex_type = types[alias_type.name]
          unless compatible_args?(ex_type.args, alias_type.args)
            diagnostics[alias_type.name] ||=
              Diagnostic.new(type_name: alias_type.name, nonregular_type: alias_type)
          end

          return
        else
          types[alias_type.name] = alias_type
        end

        expanded = builder.expand_alias2(alias_type.name, alias_type.args)
        each_alias_type(expanded) do |at|
          validate_alias_type(at, names, types)
        end
      end
    end

    def build_alias_type(name)
      entry = env.alias_decls[name] or return
      unless entry.decl.type_params.empty?
        as = entry.decl.type_params.each.map {|param| Types::Variable.new(name: param.name, location: nil) }
        Types::Alias.new(name: name, args: as, location: nil)
      end
    end

    def compatible_args?(args1, args2)
      if args1.size == args2.size
        args1.zip(args2).all? do |t1, t2|
          t1.is_a?(Types::Bases::Any) ||
            t2.is_a?(Types::Bases::Any) ||
            t1 == t2
        end
      end
    end

    def nonregular?(type_name)
      diagnostics[type_name]
    end

    def each_mutual_alias_defs(&block)
      # @type var each_node: TSort::_EachNode[TypeName]
      each_node = __skip__ = -> (&block) do
        env.alias_decls.each_value do |decl|
          block[decl.name]
        end
      end
      # @type var each_child: TSort::_EachChild[TypeName]
      each_child = __skip__ = -> (name, &block) do
        if env.alias_decls.key?(name)
          type = builder.expand_alias1(name)
          each_alias_type(type) do |ty|
            block[ty.name]
          end
        end
      end

      TSort.each_strongly_connected_component(each_node, each_child) do |names|
        yield Set.new(names)
      end
    end

    def each_alias_type(type, &block)
      if type.is_a?(RBS::Types::Alias)
        yield type
      end

      type.each_type do |ty|
        each_alias_type(ty, &block)
      end
    end

    def self.validate(env:)
      self.new(env: env).tap do |validator|
        validator.validate()
      end
    end
  end
end
