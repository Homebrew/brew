# frozen_string_literal: true

module RBS
  class EnvironmentWalker
    InstanceNode = _ = Struct.new(:type_name, keyword_init: true)
    SingletonNode = _ = Struct.new(:type_name, keyword_init: true)
    TypeNameNode = _ = Struct.new(:type_name, keyword_init: true)

    attr_reader :env

    def initialize(env:)
      @env = env
      @only_ancestors = false
    end

    def builder
      @builder ||= DefinitionBuilder.new(env: env)
    end

    def only_ancestors!(only = true)
      @only_ancestors = only
      self
    end

    def only_ancestors?
      @only_ancestors
    end

    include TSort

    def tsort_each_node(&block)
      env.class_decls.each_key do |type_name|
        yield InstanceNode.new(type_name: type_name)
        yield SingletonNode.new(type_name: type_name)
      end
      env.interface_decls.each_key do |type_name|
        yield TypeNameNode.new(type_name: type_name)
      end
      env.alias_decls.each_key do |type_name|
        yield TypeNameNode.new(type_name: type_name)
      end
    end

    def tsort_each_child(node, &block)
      name = node.type_name

      unless name.namespace.empty?
        yield SingletonNode.new(type_name: name.namespace.to_type_name)
      end

      case node
      when TypeNameNode
        case
        when name.interface?
          definition = builder.build_interface(name)
          unless only_ancestors?
            definition.each_type do |type|
              each_type_node type, &block
            end
          end
        when name.alias?
          each_type_node builder.expand_alias1(name), &block
        else
          raise "Unexpected TypeNameNode with type_name=#{name}"
        end

      when InstanceNode, SingletonNode
        definition = if node.is_a?(InstanceNode)
                       builder.build_instance(name)
                     else
                       builder.build_singleton(name)
                     end

        if ancestors = definition.ancestors
          ancestors.ancestors.each do |ancestor|
            case ancestor
            when Definition::Ancestor::Instance
              yield InstanceNode.new(type_name: ancestor.name)

              unless only_ancestors?
                ancestor.args.each do |type|
                  each_type_node type, &block
                end
              end
            when Definition::Ancestor::Singleton
              yield SingletonNode.new(type_name: ancestor.name)
            end
          end
        end

        unless only_ancestors?
          definition.each_type do |type|
            each_type_node type, &block
          end
        end
      end
    end

    def each_type_name(type, &block)
      each_type_node(type) do |node|
        yield node.type_name
      end
    end

    def each_type_node(type, &block)
      case type
      when RBS::Types::Bases::Any
      when RBS::Types::Bases::Class
      when RBS::Types::Bases::Instance
      when RBS::Types::Bases::Self
      when RBS::Types::Bases::Top
      when RBS::Types::Bases::Bottom
      when RBS::Types::Bases::Bool
      when RBS::Types::Bases::Void
      when RBS::Types::Bases::Nil
      when RBS::Types::Variable
      when RBS::Types::ClassSingleton
        yield SingletonNode.new(type_name: type.name)
      when RBS::Types::ClassInstance
        yield InstanceNode.new(type_name: type.name)
        type.args.each do |ty|
          each_type_node(ty, &block)
        end
      when RBS::Types::Interface
        yield TypeNameNode.new(type_name: type.name)
        type.args.each do |ty|
          each_type_node(ty, &block)
        end
      when RBS::Types::Alias
        yield TypeNameNode.new(type_name: type.name)
        type.args.each do |ty|
          each_type_node(ty, &block)
        end
      when RBS::Types::Union, RBS::Types::Intersection, RBS::Types::Tuple
        type.types.each do |ty|
          each_type_node ty, &block
        end
      when RBS::Types::Optional
        each_type_node type.type, &block
      when RBS::Types::Literal
        # nop
      when RBS::Types::Record
        type.fields.each_value do |ty|
          each_type_node ty, &block
        end
      when RBS::Types::Proc
        type.each_type do |ty|
          each_type_node ty, &block
        end
      else
        raise "Unexpected type given: #{type}"
      end
    end
  end
end
