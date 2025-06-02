# frozen_string_literal: true

module RBS
  class AncestorGraph
    InstanceNode = _ = Struct.new(:type_name, keyword_init: true)
    SingletonNode = _ = Struct.new(:type_name, keyword_init: true)

    attr_reader :env
    attr_reader :ancestor_builder
    attr_reader :parents
    attr_reader :children

    def initialize(env:, ancestor_builder: DefinitionBuilder::AncestorBuilder.new(env: env))
      @env = env
      @ancestor_builder = ancestor_builder
      build()
    end

    def build()
      @parents = {}
      @children = {}

      env.class_decls.each_key do |type_name|
        build_ancestors(InstanceNode.new(type_name: type_name), ancestor_builder.one_instance_ancestors(type_name))
        build_ancestors(SingletonNode.new(type_name: type_name), ancestor_builder.one_singleton_ancestors(type_name))
      end
      env.interface_decls.each_key do |type_name|
        build_ancestors(InstanceNode.new(type_name: type_name), ancestor_builder.one_interface_ancestors(type_name))
      end
    end

    def build_ancestors(node, ancestors)
      ancestors.each_ancestor do |ancestor|
        case ancestor
        when Definition::Ancestor::Instance
          register(child: node, parent: InstanceNode.new(type_name: ancestor.name))
        when Definition::Ancestor::Singleton
          register(child: node, parent: SingletonNode.new(type_name: ancestor.name))
        end
      end
    end

    def register(parent:, child:)
      (parents[child] ||= Set[]) << parent
      (children[parent] ||= Set[]) << child
    end

    def each_parent(node, &block)
      if block
        parents[node]&.each(&block)
      else
        enum_for :each_parent, node
      end
    end

    def each_child(node, &block)
      if block
        children[node]&.each(&block)
      else
        enum_for :each_child, node
      end
    end

    def each_ancestor(node, yielded: Set[], &block)
      if block
        each_parent(node) do |parent|
          unless yielded.member?(parent)
            yielded << parent
            yield parent
            each_ancestor(parent, yielded: yielded, &block)
          end
        end
      else
        enum_for :each_ancestor, node
      end
    end

    def each_descendant(node, yielded: Set[], &block)
      if block
        each_child(node) do |child|
          unless yielded.member?(child)
            yielded << child
            yield child
            each_descendant(child, yielded: yielded, &block)
          end
        end
      else
        enum_for :each_descendant, node
      end
    end
  end
end
