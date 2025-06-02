# frozen_string_literal: true

module RBS
  module Prototype
    class Runtime
      include Helpers

      attr_reader :patterns
      attr_reader :env
      attr_reader :merge
      attr_reader :owners_included

      def initialize(patterns:, env:, merge:, owners_included: [])
        @patterns = patterns
        @decls = nil
        @modules = []
        @env = env
        @merge = merge
        @owners_included = owners_included.map do |name|
          Object.const_get(name)
        end
      end

      def target?(const)
        name = const_name(const)
        return false unless name

        patterns.any? do |pattern|
          if pattern.end_with?("*")
            (name || "").start_with?(pattern.chop)
          else
            name == pattern
          end
        end
      end

      def builder
        @builder ||= DefinitionBuilder.new(env: env)
      end

      def parse(file)
        require file
      end

      def decls
        unless @decls
          @decls = []
          @modules = ObjectSpace.each_object(Module).to_a
          @modules.select {|mod| target?(mod) }.sort_by{|mod| const_name(mod) }.each do |mod|
            case mod
            when Class
              generate_class mod
            when Module
              generate_module mod
            end
          end
        end

        @decls
      end

      def to_type_name(name, full_name: false)
        *prefix, last = name.split(/::/)

        if full_name
          if prefix.empty?
            TypeName.new(name: last.to_sym, namespace: Namespace.empty)
          else
            TypeName.new(name: last.to_sym, namespace: Namespace.parse(prefix.join("::")))
          end
        else
          TypeName.new(name: last.to_sym, namespace: Namespace.empty)
        end
      end

      def each_included_module(type_name, mod)
        supers = Set[]

        mod.included_modules.each do |mix|
          supers.merge(mix.included_modules)
        end

        if mod.is_a?(Class) && mod.superclass
          mod.superclass.included_modules.each do |mix|
            supers << mix
            supers.merge(mix.included_modules)
          end
        end

        mod.included_modules.each do |mix|
          unless supers.include?(mix)
            unless const_name(mix)
              RBS.logger.warn("Skipping anonymous module #{mix} included in #{mod}")
            else
              module_name = module_full_name = to_type_name(const_name(mix), full_name: true)
              if module_full_name.namespace == type_name.namespace
                module_name = TypeName.new(name: module_full_name.name, namespace: Namespace.empty)
              end

              yield module_name, module_full_name, mix
            end
          end
        end
      end

      def method_type(method)
        untyped = Types::Bases::Any.new(location: nil)

        required_positionals = []
        optional_positionals = []
        rest = nil
        trailing_positionals = []
        required_keywords = {}
        optional_keywords = {}
        rest_keywords = nil

        requireds = required_positionals

        block = nil

        method.parameters.each do |kind, name|
          case kind
          when :req
            requireds << Types::Function::Param.new(name: name, type: untyped)
          when :opt
            requireds = trailing_positionals
            optional_positionals << Types::Function::Param.new(name: name, type: untyped)
          when :rest
            requireds = trailing_positionals
            name = nil if name == :* # For `def f(...) end` syntax
            rest = Types::Function::Param.new(name: name, type: untyped)
          when :keyreq
            required_keywords[name] = Types::Function::Param.new(name: nil, type: untyped)
          when :key
            optional_keywords[name] = Types::Function::Param.new(name: nil, type: untyped)
          when :keyrest
            rest_keywords = Types::Function::Param.new(name: nil, type: untyped)
          when :block
            block = Types::Block.new(
              type: Types::Function.empty(untyped).update(rest_positionals: Types::Function::Param.new(name: nil, type: untyped)),
              required: true,
              self_type: nil
            )
          end
        end

        block ||= block_from_ast_of(method)

        return_type = if method.name == :initialize
                        Types::Bases::Void.new(location: nil)
                      else
                        untyped
                      end
        method_type = Types::Function.new(
          required_positionals: required_positionals,
          optional_positionals: optional_positionals,
          rest_positionals: rest,
          trailing_positionals: trailing_positionals,
          required_keywords: required_keywords,
          optional_keywords: optional_keywords,
          rest_keywords: rest_keywords,
          return_type: return_type,
        )

        MethodType.new(
          location: nil,
          type_params: [],
          type: method_type,
          block: block
        )
      end

      def merge_rbs(module_name, members, instance: nil, singleton: nil)
        if merge
          if env.class_decls[module_name.absolute!]
            case
            when instance
              method = builder.build_instance(module_name.absolute!).methods[instance]
              method_name = instance
              kind = :instance
            when singleton
              method = builder.build_singleton(module_name.absolute!).methods[singleton]
              method_name = singleton
              kind = :singleton
            end

            if method
              members << AST::Members::MethodDefinition.new(
                name: method_name,
                types: method.method_types.map {|type|
                  type.update.tap do |ty|
                    def ty.to_s
                      location.source
                    end
                  end
                },
                kind: kind,
                location: nil,
                comment: method.comments[0],
                annotations: method.annotations,
                overload: false
              )
              return
            end
          end

          yield
        else
          yield
        end
      end

      def target_method?(mod, instance: nil, singleton: nil)
        case
        when instance
          method = mod.instance_method(instance)
          method.owner == mod || owners_included.any? {|m| method.owner == m }
        when singleton
          method = mod.singleton_class.instance_method(singleton)
          method.owner == mod.singleton_class || owners_included.any? {|m| method.owner == m.singleton_class }
        end
      end

      def generate_methods(mod, module_name, members)
        mod.singleton_methods.select {|name| target_method?(mod, singleton: name) }.sort.each do |name|
          method = mod.singleton_class.instance_method(name)

          if method.name == method.original_name
            merge_rbs(module_name, members, singleton: name) do
              RBS.logger.info "missing #{module_name}.#{name} #{method.source_location}"

              members << AST::Members::MethodDefinition.new(
                name: method.name,
                types: [method_type(method)],
                kind: :singleton,
                location: nil,
                comment: nil,
                annotations: [],
                overload: false
              )
            end
          else
            members << AST::Members::Alias.new(
              new_name: method.name,
              old_name: method.original_name,
              kind: :singleton,
              location: nil,
              comment: nil,
              annotations: [],
              )
          end
        end

        public_instance_methods = mod.public_instance_methods.select {|name| target_method?(mod, instance: name) }
        unless public_instance_methods.empty?
          members << AST::Members::Public.new(location: nil)

          public_instance_methods.sort.each do |name|
            method = mod.instance_method(name)

            if method.name == method.original_name
              merge_rbs(module_name, members, instance: name) do
                RBS.logger.info "missing #{module_name}##{name} #{method.source_location}"

                members << AST::Members::MethodDefinition.new(
                  name: method.name,
                  types: [method_type(method)],
                  kind: :instance,
                  location: nil,
                  comment: nil,
                  annotations: [],
                  overload: false
                )
              end
            else
              members << AST::Members::Alias.new(
                new_name: method.name,
                old_name: method.original_name,
                kind: :instance,
                location: nil,
                comment: nil,
                annotations: [],
                )
            end
          end
        end

        private_instance_methods = mod.private_instance_methods.select {|name| target_method?(mod, instance: name) }
        unless private_instance_methods.empty?
          members << AST::Members::Private.new(location: nil)

          private_instance_methods.sort.each do |name|
            method = mod.instance_method(name)

            if method.name == method.original_name
              merge_rbs(module_name, members, instance: name) do
                RBS.logger.info "missing #{module_name}##{name} #{method.source_location}"

                members << AST::Members::MethodDefinition.new(
                  name: method.name,
                  types: [method_type(method)],
                  kind: :instance,
                  location: nil,
                  comment: nil,
                  annotations: [],
                  overload: false
                )
              end
            else
              members << AST::Members::Alias.new(
                new_name: method.name,
                old_name: method.original_name,
                kind: :instance,
                location: nil,
                comment: nil,
                annotations: [],
                )
            end
          end
        end
      end

      def generate_constants(mod, decls)
        mod.constants(false).sort.each do |name|
          begin
            value = mod.const_get(name)
          rescue StandardError, LoadError => e
            RBS.logger.warn("Skipping constant #{name} of #{mod} since #{e}")
            next
          end

          next if value.is_a?(Class) || value.is_a?(Module)
          unless value.class.name
            RBS.logger.warn("Skipping constant #{name} #{value} of #{mod} as an instance of anonymous class")
            next
          end

          type = case value
                 when true, false
                   Types::Bases::Bool.new(location: nil)
                 when nil
                   Types::Optional.new(
                     type: Types::Bases::Any.new(location: nil),
                     location: nil
                   )
                 else
                   value_type_name = to_type_name(const_name(value.class))
                   args = type_args(value_type_name)
                   Types::ClassInstance.new(name: value_type_name, args: args, location: nil)
                 end

          decls << AST::Declarations::Constant.new(
            name: to_type_name(name.to_s),
            type: type,
            location: nil,
            comment: nil
          )
        end
      end

      def generate_super_class(mod)
        if mod.superclass.nil? || mod.superclass == ::Object
          nil
        elsif const_name(mod.superclass).nil?
          RBS.logger.warn("Skipping anonymous superclass #{mod.superclass} of #{mod}")
          nil
        else
          super_name = to_type_name(const_name(mod.superclass), full_name: true)
          super_args = type_args(super_name)
          AST::Declarations::Class::Super.new(name: super_name, args: super_args, location: nil)
        end
      end

      def generate_class(mod)
        type_name = to_type_name(const_name(mod))
        outer_decls = ensure_outer_module_declarations(mod)

        # Check if a declaration exists for the actual module
        decl = outer_decls.detect { |decl| decl.is_a?(AST::Declarations::Class) && decl.name.name == only_name(mod).to_sym }
        unless decl
          decl = AST::Declarations::Class.new(
            name: to_type_name(only_name(mod)),
            type_params: [],
            super_class: generate_super_class(mod),
            members: [],
            annotations: [],
            location: nil,
            comment: nil
          )

          outer_decls << decl
        end

        each_included_module(type_name, mod) do |module_name, module_full_name, _|
          args = type_args(module_full_name)
          decl.members << AST::Members::Include.new(
            name: module_name,
            args: args,
            location: nil,
            comment: nil,
            annotations: []
          )
        end

        each_included_module(type_name, mod.singleton_class) do |module_name, module_full_name ,_|
          args = type_args(module_full_name)
          decl.members << AST::Members::Extend.new(
            name: module_name,
            args: args,
            location: nil,
            comment: nil,
            annotations: []
          )
        end

        generate_methods(mod, type_name, decl.members)

        generate_constants mod, decl.members
      end

      def generate_module(mod)
        name = const_name(mod)

        unless name
          RBS.logger.warn("Skipping anonymous module #{mod}")
          return
        end

        type_name = to_type_name(name)
        outer_decls = ensure_outer_module_declarations(mod)

        # Check if a declaration exists for the actual class
        decl = outer_decls.detect { |decl| decl.is_a?(AST::Declarations::Module) && decl.name.name == only_name(mod).to_sym }
        unless decl
          decl = AST::Declarations::Module.new(
            name: to_type_name(only_name(mod)),
            type_params: [],
            self_types: [],
            members: [],
            annotations: [],
            location: nil,
            comment: nil
          )

          outer_decls << decl
        end

        each_included_module(type_name, mod) do |module_name, module_full_name, _|
          args = type_args(module_full_name)
          decl.members << AST::Members::Include.new(
            name: module_name,
            args: args,
            location: nil,
            comment: nil,
            annotations: []
          )
        end

        each_included_module(type_name, mod.singleton_class) do |module_name, module_full_name, _|
          args = type_args(module_full_name)
          decl.members << AST::Members::Extend.new(
            name: module_name,
            args: args,
            location: nil,
            comment: nil,
            annotations: []
          )
        end

        generate_methods(mod, type_name, decl.members)

        generate_constants mod, decl.members
      end

      # Generate/find outer module declarations
      # This is broken down into another method to comply with `DRY`
      # This generates/finds declarations in nested form & returns the last array of declarations
      def ensure_outer_module_declarations(mod)
        *outer_module_names, _ = const_name(mod).split(/::/) #=> parent = [A, B], mod = C
        destination = @decls # Copy the entries in ivar @decls, not .dup

        outer_module_names&.each_with_index do |outer_module_name, i|
          current_name = outer_module_names[0, i + 1].join('::')
          outer_module = @modules.detect { |x| const_name(x) == current_name }
          outer_decl = destination.detect { |decl| decl.is_a?(outer_module.is_a?(Class) ? AST::Declarations::Class : AST::Declarations::Module) && decl.name.name == outer_module_name.to_sym }

          # Insert AST::Declarations if declarations are not added previously
          unless outer_decl
            if outer_module.is_a?(Class)
              outer_decl = AST::Declarations::Class.new(
                name: to_type_name(outer_module_name),
                type_params: [],
                super_class: generate_super_class(outer_module),
                members: [],
                annotations: [],
                location: nil,
                comment: nil
              )
            else
              outer_decl = AST::Declarations::Module.new(
                name: to_type_name(outer_module_name),
                type_params: [],
                self_types: [],
                members: [],
                annotations: [],
                location: nil,
                comment: nil
              )
            end

            destination << outer_decl
          end

          destination = outer_decl.members
        end

        # Return the array of declarations checked out at the end
        destination
      end

      # Returns the exact name & not compactly declared name
      def only_name(mod)
        # No nil check because this method is invoked after checking if the module exists
        const_name(mod).split(/::/).last # (A::B::C) => C
      end

      def const_name(const)
        @module_name_method ||= Module.instance_method(:name)
        @module_name_method.bind(const).call
      end

      def type_args(type_name)
        if class_decl = env.class_decls[type_name.absolute!]
          class_decl.type_params.size.times.map { :untyped }
        else
          []
        end
      end

      def block_from_ast_of(method)
        return nil if RUBY_VERSION < '3.1'

        begin
          ast = RubyVM::AbstractSyntaxTree.of(method)
        rescue ArgumentError
          return # When the method is defined in eval
        end

        block_from_body(ast) if ast&.type == :SCOPE
      end
    end
  end
end
