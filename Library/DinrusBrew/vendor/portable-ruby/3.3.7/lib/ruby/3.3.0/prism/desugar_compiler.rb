# frozen_string_literal: true

module Prism
  # DesugarCompiler is a compiler that desugars Ruby code into a more primitive
  # form. This is useful for consumers that want to deal with fewer node types.
  class DesugarCompiler < MutationCompiler
    # @@foo &&= bar
    #
    # becomes
    #
    # @@foo && @@foo = bar
    def visit_class_variable_and_write_node(node)
      desugar_and_write_node(node, ClassVariableReadNode, ClassVariableWriteNode, node.name)
    end

    # @@foo ||= bar
    #
    # becomes
    #
    # defined?(@@foo) ? @@foo : @@foo = bar
    def visit_class_variable_or_write_node(node)
      desugar_or_write_defined_node(node, ClassVariableReadNode, ClassVariableWriteNode, node.name)
    end

    # @@foo += bar
    #
    # becomes
    #
    # @@foo = @@foo + bar
    def visit_class_variable_operator_write_node(node)
      desugar_operator_write_node(node, ClassVariableReadNode, ClassVariableWriteNode, node.name)
    end

    # Foo &&= bar
    #
    # becomes
    #
    # Foo && Foo = bar
    def visit_constant_and_write_node(node)
      desugar_and_write_node(node, ConstantReadNode, ConstantWriteNode, node.name)
    end

    # Foo ||= bar
    #
    # becomes
    #
    # defined?(Foo) ? Foo : Foo = bar
    def visit_constant_or_write_node(node)
      desugar_or_write_defined_node(node, ConstantReadNode, ConstantWriteNode, node.name)
    end

    # Foo += bar
    #
    # becomes
    #
    # Foo = Foo + bar
    def visit_constant_operator_write_node(node)
      desugar_operator_write_node(node, ConstantReadNode, ConstantWriteNode, node.name)
    end

    # $foo &&= bar
    #
    # becomes
    #
    # $foo && $foo = bar
    def visit_global_variable_and_write_node(node)
      desugar_and_write_node(node, GlobalVariableReadNode, GlobalVariableWriteNode, node.name)
    end

    # $foo ||= bar
    #
    # becomes
    #
    # defined?($foo) ? $foo : $foo = bar
    def visit_global_variable_or_write_node(node)
      desugar_or_write_defined_node(node, GlobalVariableReadNode, GlobalVariableWriteNode, node.name)
    end

    # $foo += bar
    #
    # becomes
    #
    # $foo = $foo + bar
    def visit_global_variable_operator_write_node(node)
      desugar_operator_write_node(node, GlobalVariableReadNode, GlobalVariableWriteNode, node.name)
    end

    # @foo &&= bar
    #
    # becomes
    #
    # @foo && @foo = bar
    def visit_instance_variable_and_write_node(node)
      desugar_and_write_node(node, InstanceVariableReadNode, InstanceVariableWriteNode, node.name)
    end

    # @foo ||= bar
    #
    # becomes
    #
    # @foo || @foo = bar
    def visit_instance_variable_or_write_node(node)
      desugar_or_write_node(node, InstanceVariableReadNode, InstanceVariableWriteNode, node.name)
    end

    # @foo += bar
    #
    # becomes
    #
    # @foo = @foo + bar
    def visit_instance_variable_operator_write_node(node)
      desugar_operator_write_node(node, InstanceVariableReadNode, InstanceVariableWriteNode, node.name)
    end

    # foo &&= bar
    #
    # becomes
    #
    # foo && foo = bar
    def visit_local_variable_and_write_node(node)
      desugar_and_write_node(node, LocalVariableReadNode, LocalVariableWriteNode, node.name, node.depth)
    end

    # foo ||= bar
    #
    # becomes
    #
    # foo || foo = bar
    def visit_local_variable_or_write_node(node)
      desugar_or_write_node(node, LocalVariableReadNode, LocalVariableWriteNode, node.name, node.depth)
    end

    # foo += bar
    #
    # becomes
    #
    # foo = foo + bar
    def visit_local_variable_operator_write_node(node)
      desugar_operator_write_node(node, LocalVariableReadNode, LocalVariableWriteNode, node.name, node.depth)
    end

    private

    # Desugar `x &&= y` to `x && x = y`
    def desugar_and_write_node(node, read_class, write_class, *arguments)
      AndNode.new(
        read_class.new(*arguments, node.name_loc),
        write_class.new(*arguments, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Desugar `x += y` to `x = x + y`
    def desugar_operator_write_node(node, read_class, write_class, *arguments)
      write_class.new(
        *arguments,
        node.name_loc,
        CallNode.new(
          0,
          read_class.new(*arguments, node.name_loc),
          nil,
          node.operator_loc.slice.chomp("="),
          node.operator_loc.copy(length: node.operator_loc.length - 1),
          nil,
          ArgumentsNode.new(0, [node.value], node.value.location),
          nil,
          nil,
          node.location
        ),
        node.operator_loc.copy(start_offset: node.operator_loc.end_offset - 1, length: 1),
        node.location
      )
    end

    # Desugar `x ||= y` to `x || x = y`
    def desugar_or_write_node(node, read_class, write_class, *arguments)
      OrNode.new(
        read_class.new(*arguments, node.name_loc),
        write_class.new(*arguments, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Desugar `x ||= y` to `defined?(x) ? x : x = y`
    def desugar_or_write_defined_node(node, read_class, write_class, *arguments)
      IfNode.new(
        node.operator_loc,
        DefinedNode.new(nil, read_class.new(*arguments, node.name_loc), nil, node.operator_loc, node.name_loc),
        node.operator_loc,
        StatementsNode.new([read_class.new(*arguments, node.name_loc)], node.location),
        ElseNode.new(
          node.operator_loc,
          StatementsNode.new(
            [write_class.new(*arguments, node.name_loc, node.value, node.operator_loc, node.location)],
            node.location
          ),
          node.operator_loc,
          node.location
        ),
        node.operator_loc,
        node.location
      )
    end
  end
end
