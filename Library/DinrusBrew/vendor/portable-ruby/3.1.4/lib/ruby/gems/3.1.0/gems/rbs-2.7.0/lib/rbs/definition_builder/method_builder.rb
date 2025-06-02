# frozen_string_literal: true

module RBS
  class DefinitionBuilder
    class MethodBuilder
      class Methods
        Definition = _ = Struct.new(:name, :type, :originals, :overloads, :accessibilities, keyword_init: true) do
          # @implements Definition

          def original
            originals.first
          end

          def accessibility
            if original.is_a?(AST::Members::Alias)
              raise "alias member doesn't have accessibility"
            else
              accessibilities[0] or raise
            end
          end

          def self.empty(name:, type:)
            new(type: type, name: name, originals: [], overloads: [], accessibilities: [])
          end
        end

        attr_reader :type
        attr_reader :methods

        def initialize(type:)
          @type = type
          @methods = {}
        end

        def validate!
          methods.each_value do |defn|
            if defn.originals.size > 1
              raise DuplicatedMethodDefinitionError.new(
                type: type,
                method_name: defn.name,
                members: defn.originals
              )
            end
          end

          self
        end

        def each
          if block_given?
            Sorter.new(methods).each_strongly_connected_component do |scc|
              if scc.size > 1
                raise RecursiveAliasDefinitionError.new(type: type, defs: scc)
              end

              yield scc[0]
            end
          else
            enum_for :each
          end
        end

        class Sorter
          include TSort

          attr_reader :methods

          def initialize(methods)
            @methods = methods
          end

          def tsort_each_node(&block)
            methods.each_value(&block)
          end

          def tsort_each_child(defn)
            if (member = defn.original).is_a?(AST::Members::Alias)
              if old = methods[member.old_name]
                yield old
              end
            end
          end
        end
      end

      attr_reader :env
      attr_reader :instance_methods
      attr_reader :singleton_methods
      attr_reader :interface_methods

      def initialize(env:)
        @env = env

        @instance_methods = {}
        @singleton_methods = {}
        @interface_methods = {}
      end

      def build_instance(type_name)
        instance_methods[type_name] ||=
          begin
            entry = env.class_decls[type_name]
            args = entry.type_params.map {|param| Types::Variable.new(name: param.name, location: param.location) }
            type = Types::ClassInstance.new(name: type_name, args: args, location: nil)
            Methods.new(type: type).tap do |methods|
              entry.decls.each do |d|
                subst = Substitution.build(d.decl.type_params.each.map(&:name), args)
                each_member_with_accessibility(d.decl.members) do |member, accessibility|
                  case member
                  when AST::Members::MethodDefinition
                    case member.kind
                    when :instance
                      build_method(
                        methods,
                        type,
                        member: member.update(types: member.types.map {|type| type.sub(subst) }),
                        accessibility: member.visibility || accessibility
                      )
                    when :singleton_instance
                      build_method(
                        methods,
                        type,
                        member: member.update(types: member.types.map {|type| type.sub(subst) }),
                        accessibility: :private
                      )
                    end
                  when AST::Members::AttrReader, AST::Members::AttrWriter, AST::Members::AttrAccessor
                    if member.kind == :instance
                      build_attribute(methods,
                                      type,
                                      member: member.update(type: member.type.sub(subst)),
                                      accessibility: member.visibility || accessibility)
                    end
                  when AST::Members::Alias
                    if member.kind == :instance
                      build_alias(methods, type, member: member)
                    end
                  end
                end
              end
            end.validate!
          end
      end

      def build_singleton(type_name)
        singleton_methods[type_name] ||=
          begin
            entry = env.class_decls[type_name]
            type = Types::ClassSingleton.new(name: type_name, location: nil)

            Methods.new(type: type).tap do |methods|
              entry.decls.each do |d|
                d.decl.members.each do |member|
                  case member
                  when AST::Members::MethodDefinition
                    if member.singleton?
                      build_method(methods, type, member: member, accessibility: member.visibility || :public)
                    end
                  when AST::Members::AttrReader, AST::Members::AttrWriter, AST::Members::AttrAccessor
                    if member.kind == :singleton
                      build_attribute(methods, type, member: member, accessibility: member.visibility || :public)
                    end
                  when AST::Members::Alias
                    if member.kind == :singleton
                      build_alias(methods, type, member: member)
                    end
                  end
                end
              end
            end.validate!
          end
      end

      def build_interface(type_name)
        interface_methods[type_name] ||=
          begin
            entry = env.interface_decls[type_name]
            args = Types::Variable.build(entry.decl.type_params.each.map(&:name))
            type = Types::Interface.new(name: type_name, args: args, location: nil)

            Methods.new(type: type).tap do |methods|
              entry.decl.members.each do |member|
                case member
                when AST::Members::MethodDefinition
                  build_method(methods, type, member: member, accessibility: :public)
                when AST::Members::Alias
                  build_alias(methods, type, member: member)
                end
              end
            end.validate!
          end
      end

      def build_alias(methods, type, member:)
        defn = methods.methods[member.new_name] ||= Methods::Definition.empty(type: type, name: member.new_name)
        defn.originals << member
      end

      def build_attribute(methods, type, member:, accessibility:)
        if member.is_a?(AST::Members::AttrReader) || member.is_a?(AST::Members::AttrAccessor)
          defn = methods.methods[member.name] ||= Methods::Definition.empty(type: type, name: member.name)

          defn.accessibilities << accessibility
          defn.originals << member
        end

        if member.is_a?(AST::Members::AttrWriter) || member.is_a?(AST::Members::AttrAccessor)
          defn = methods.methods[:"#{member.name}="] ||= Methods::Definition.empty(type: type, name: :"#{member.name}=")

          defn.accessibilities << accessibility
          defn.originals << member
        end
      end

      def build_method(methods, type, member:, accessibility:)
        defn = methods.methods[member.name] ||= Methods::Definition.empty(type: type, name: member.name)

        if member.overload?
          defn.overloads << member
        else
          defn.accessibilities << accessibility
          defn.originals << member
        end
      end

      def each_member_with_accessibility(members, accessibility: :public)
        members.each do |member|
          case member
          when AST::Members::Public
            accessibility = :public
          when AST::Members::Private
            accessibility = :private
          else
            yield member, accessibility
          end
        end
      end

      def update(env:, except:)
        MethodBuilder.new(env: env).tap do |copy|
          copy.instance_methods.merge!(instance_methods)
          copy.singleton_methods.merge!(singleton_methods)
          copy.interface_methods.merge!(interface_methods)

          except.each do |type_name|
            copy.instance_methods.delete(type_name)
            copy.singleton_methods.delete(type_name)
            copy.interface_methods.delete(type_name)
          end
        end
      end
    end
  end
end
