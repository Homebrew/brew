# typed: strict
# frozen_string_literal: true

# Parlour type signature generator plugin for Homebrew DSL attributes.
class Attr < Parlour::Plugin
  sig { override.params(root: Parlour::RbiGenerator::Namespace).void }
  def generate(root)
    tree = T.let([], T::Array[T.untyped])
    Homebrew::Parlour.ast_list.each do |node|
      tree += find_custom_attr(node)
    end
    process_custom_attr(tree, root)
  end

  sig { override.returns(T.nilable(String)) }
  def strictness
    "strict"
  end

  private

  sig { params(node: Parser::AST::Node, list: T::Array[String]).returns(T::Array[String]) }
  def traverse_module_name(node, list = [])
    parent, name = node.children
    list = traverse_module_name(parent, list) if parent
    list << name.to_s
    list
  end

  sig { params(node: T.nilable(Parser::AST::Node)).returns(T.nilable(String)) }
  def extract_module_name(node)
    return if node.nil?

    traverse_module_name(node).join("::")
  end

  sig { params(node: Parser::AST::Node).returns(T::Array[T.untyped]) }
  def find_custom_attr(node)
    tree = T.let([], T::Array[T.untyped])
    children = node.children.dup

    if node.type == :begin
      children.each do |child|
        subtree = find_custom_attr(child)
        tree += subtree unless subtree.empty?
      end
    elsif node.type == :sclass
      subtree = find_custom_attr(node.children[1])
      return tree if subtree.empty?

      tree << [:sclass, subtree]
    elsif node.type == :class || node.type == :module
      element = []
      case node.type
      when :class
        element << :class
        element << extract_module_name(children.shift)
        element << extract_module_name(children.shift)
      when :module
        element << :module
        element << extract_module_name(children.shift)
      end

      body = children.shift
      return tree if body.nil?

      subtree = find_custom_attr(body)
      return tree if subtree.empty?

      element << subtree
      tree << element
    elsif node.type == :send && children.shift.nil?
      method_name = children.shift

      case method_name
      when :attr_rw, :attr_predicate
        children.each do |name_node|
          tree << [method_name, name_node.children.first.to_s]
        end
      when :delegate
        children.each do |name_node|
          name_node.children.each do |pair|
            delegated_method = pair.children.first
            delegated_methods = if delegated_method.type == :array
              delegated_method.children
            else
              [delegated_method]
            end

            delegated_methods.each do |delegated_method_sym|
              tree << [method_name, delegated_method_sym.children.first.to_s]
            end
          end
        end
      end
    end

    tree
  end

  ARRAY_METHODS = T.let(["to_a", "to_ary"].freeze, T::Array[String])
  HASH_METHODS = T.let(["to_h", "to_hash"].freeze, T::Array[String])
  STRING_METHODS = T.let(["to_s", "to_str", "to_json"].freeze, T::Array[String])

  sig { params(tree: T::Array[T.untyped], namespace: Parlour::RbiGenerator::Namespace, sclass: T::Boolean).void }
  def process_custom_attr(tree, namespace, sclass: false)
    tree.each do |node|
      type = node.shift
      case type
      when :sclass
        process_custom_attr(node.shift, namespace, sclass: true)
      when :class
        class_namespace = namespace.create_class(node.shift, superclass: node.shift)
        process_custom_attr(node.shift, class_namespace)
      when :module
        module_namespace = namespace.create_module(node.shift)
        process_custom_attr(node.shift, module_namespace)
      when :attr_rw
        name = node.shift
        name = "self.#{name}" if sclass
        namespace.create_method(name,
                                parameters:  [
                                  Parlour::RbiGenerator::Parameter.new("arg", type:    "T.untyped",
                                                                              default: "T.unsafe(nil)"),
                                ],
                                return_type: "T.untyped")
      when :attr_predicate
        name = node.shift
        name = "self.#{name}" if sclass
        namespace.create_method(name, return_type: "T::Boolean")
      when :delegate
        name = node.shift

        return_type = if name.end_with?("?")
          "T::Boolean"
        elsif ARRAY_METHODS.include?(name)
          "Array"
        elsif HASH_METHODS.include?(name)
          "Hash"
        elsif STRING_METHODS.include?(name)
          "String"
        else
          "T.untyped"
        end

        name = "self.#{name}" if sclass

        namespace.create_method(
          name,
          parameters:  [
            Parlour::RbiGenerator::Parameter.new("*args"),
            Parlour::RbiGenerator::Parameter.new("**options"),
            Parlour::RbiGenerator::Parameter.new("&block"),
          ],
          return_type:,
        )
      else
        raise "Malformed tree."
      end
    end
  end
end
