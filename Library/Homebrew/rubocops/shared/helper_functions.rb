# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "rubocop"

require_relative "../../warnings"
Warnings.ignore :parser_syntax do
  require "parser/current"
end

module RuboCop
  module Cop
    # Helper functions for cops.
    module HelperFunctions
      include RangeHelp

      # Checks for regex match of pattern in the node and
      # sets the appropriate instance variables to report the match.
      def regex_match_group(node, pattern)
        string_repr = string_content(node).encode("UTF-8", invalid: :replace)
        match_object = string_repr.match(pattern)
        return unless match_object

        node_begin_pos = start_column(node)
        line_begin_pos = line_start_column(node)
        @column = if node_begin_pos == line_begin_pos
          node_begin_pos + match_object.begin(0) - line_begin_pos
        else
          node_begin_pos + match_object.begin(0) - line_begin_pos + 1
        end
        @length = match_object.to_s.length
        @line_no = line_number(node)
        @source_buf = source_buffer(node)
        @offensive_node = node
        @offensive_source_range = T.let(
          source_range(@source_buf, @line_no, @column, @length),
          T.nilable(Parser::Source::Range),
        )
        match_object
      end

      # Returns the begin position of the node's line in source code.
      def line_start_column(node)
        node.source_range.source_buffer.line_range(node.loc.line).begin_pos
      end

      # Returns the begin position of the node in source code.
      def start_column(node)
        node.source_range.begin_pos
      end

      # Returns the line number of the node.
      sig { params(node: RuboCop::AST::Node).returns(Integer) }
      def line_number(node)
        node.loc.line
      end

      # Source buffer is required as an argument to report style violations.
      sig { params(node: RuboCop::AST::Node).returns(Parser::Source::Buffer) }
      def source_buffer(node)
        node.source_range.source_buffer
      end

      # Returns the string representation if node is of type str(plain) or dstr(interpolated) or const.
      def string_content(node, strip_dynamic: false)
        case node.type
        when :str
          node.str_content
        when :dstr
          content = ""
          node.each_child_node(:str, :begin) do |child|
            content += if child.begin_type?
              strip_dynamic ? "" : child.source
            else
              child.str_content
            end
          end
          content
        when :send
          if node.method?(:+) && (node.receiver.str_type? || node.receiver.dstr_type?)
            content = string_content(node.receiver)
            arg = node.arguments.first
            content += string_content(arg) if arg
            content
          else
            ""
          end
        when :const
          node.const_name
        when :sym
          node.children.first.to_s
        else
          ""
        end
      end

      def problem(msg, &block)
        add_offense(@offensive_node, message: msg, &block)
      end

      # Returns all string nodes among the descendants of given node.
      def find_strings(node)
        return [] if node.nil?
        return [node] if node.str_type?

        node.each_descendant(:str)
      end

      # Returns method_node matching method_name.
      def find_node_method_by_name(node, method_name)
        return if node.nil?

        node.each_child_node(:send) do |method_node|
          next if method_node.method_name != method_name

          @offensive_node = method_node
          return method_node
        end
        # If not found then, parent node becomes the offensive node
        @offensive_node = node.parent
        nil
      end

      # Gets/sets the given node as the offending node when required in custom cops.
      def offending_node(node = nil)
        return @offensive_node if node.nil?

        @offensive_node = node
      end

      # Returns an array of method call nodes matching method_name inside node with depth first order (child nodes).
      def find_method_calls_by_name(node, method_name)
        return if node.nil?

        nodes = node.each_child_node(:send).select { |method_node| method_name == method_node.method_name }

        # The top level node can be a method
        nodes << node if node.send_type? && node.method_name == method_name

        nodes
      end

      # Returns an array of method call nodes matching method_name in every descendant of node.
      # Returns every method call if no method_name is passed.
      def find_every_method_call_by_name(node, method_name = nil)
        return if node.nil?

        node.each_descendant(:send).select do |method_node|
          method_name.nil? ||
            method_name == method_node.method_name
        end
      end

      # Returns array of function call nodes matching func_name in every descendant of node.
      #
      # - matches function call: `foo(*args, **kwargs)`
      # - does not match method calls: `foo.bar(*args, **kwargs)`
      # - returns every function call if no func_name is passed
      def find_every_func_call_by_name(node, func_name = nil)
        return if node.nil?

        node.each_descendant(:send).select do |func_node|
          func_node.receiver.nil? && (func_name.nil? || func_name == func_node.method_name)
        end
      end

      # Given a method_name and arguments, yields to a block with
      # matching method passed as a parameter to the block.
      def find_method_with_args(node, method_name, *args)
        methods = find_every_method_call_by_name(node, method_name)
        methods.each do |method|
          next unless parameters_passed?(method, args)
          return true unless block_given?

          yield method
        end
      end

      # Matches a method with a receiver. Yields to a block with matching method node.
      #
      # ### Examples
      #
      # Match `Formula.factory(name)`.
      #
      # ```ruby
      # find_instance_method_call(node, "Formula", :factory)
      # ```
      #
      # Match `build.head?`.
      #
      # ```ruby
      # find_instance_method_call(node, :build, :head?)
      # ```
      def find_instance_method_call(node, instance, method_name)
        methods = find_every_method_call_by_name(node, method_name)
        methods.each do |method|
          next if method.receiver.nil?
          next if method.receiver.const_name != instance &&
                  !(method.receiver.send_type? && method.receiver.method_name == instance)

          @offensive_node = method
          return true unless block_given?

          yield method
        end
      end

      # Matches receiver part of method. Yields to a block with parent node of receiver.
      #
      # ### Example
      #
      # Match `ARGV.<whatever>()`.
      #
      # ```ruby
      # find_instance_call(node, "ARGV")
      # ```
      def find_instance_call(node, name)
        node.each_descendant(:send) do |method_node|
          next if method_node.receiver.nil?
          next if method_node.receiver.const_name != name &&
                  !(method_node.receiver.send_type? && method_node.receiver.method_name == name)

          @offensive_node = method_node.receiver
          return true unless block_given?

          yield method_node
        end
      end

      # Find CONSTANTs in the source.
      # If block given, yield matching nodes.
      def find_const(node, const_name)
        return if node.nil?

        node.each_descendant(:const) do |const_node|
          next if const_node.const_name != const_name

          @offensive_node = const_node
          yield const_node if block_given?
          return true
        end
        nil
      end

      # To compare node with appropriate Ruby variable.
      def node_equals?(node, var)
        node == Parser::CurrentRuby.parse(var.inspect)
      end

      # Returns a block named block_name inside node.
      def find_block(node, block_name)
        return if node.nil?

        node.each_child_node(:block) do |block_node|
          next if block_node.method_name != block_name

          @offensive_node = block_node
          return block_node
        end
        # If not found then, parent node becomes the offensive node
        @offensive_node = node.parent
        nil
      end

      # Returns an array of block nodes named block_name inside node.
      def find_blocks(node, block_name)
        return if node.nil?

        node.each_child_node(:block).select { |block_node| block_name == block_node.method_name }
      end

      # Returns an array of block nodes of any depth below node in AST.
      # If a block is given then yields matching block node to the block!
      def find_all_blocks(node, block_name)
        return if node.nil?

        blocks = node.each_descendant(:block).select { |block_node| block_name == block_node.method_name }
        return blocks unless block_given?

        blocks.each do |block_node|
          offending_node(block_node)
          yield block_node
        end
      end

      # Returns a method definition node with method_name.
      # Returns first method def if method_name is nil.
      def find_method_def(node, method_name = nil)
        return if node.nil?

        node.each_child_node(:def) do |def_node|
          def_method_name = method_name(def_node)
          next if method_name != def_method_name && method_name.present?

          @offensive_node = def_node
          return def_node
        end
        return if node.parent.nil?

        # If not found then, parent node becomes the offensive node
        @offensive_node = node.parent
        nil
      end

      # Check if a block method is called inside a block.
      def block_method_called_in_block?(node, method_name)
        node.body.each_child_node do |call_node|
          next if !call_node.block_type? && !call_node.send_type?
          next if call_node.method_name != method_name

          @offensive_node = call_node
          return true
        end
        false
      end

      # Check if method_name is called among the direct children nodes in the given node.
      # Check if the node itself is the method.
      def method_called?(node, method_name)
        if node.send_type? && node.method_name == method_name
          offending_node(node)
          return true
        end
        node.each_child_node(:send) do |call_node|
          next if call_node.method_name != method_name

          offending_node(call_node)
          return true
        end
        false
      end

      # Check if method_name is called among every descendant node of given node.
      def method_called_ever?(node, method_name)
        node.each_descendant(:send) do |call_node|
          next if call_node.method_name != method_name

          @offensive_node = call_node
          return true
        end
        false
      end

      # Checks for precedence; returns the first pair of precedence-violating nodes.
      def check_precedence(first_nodes, next_nodes)
        next_nodes.each do |each_next_node|
          first_nodes.each do |each_first_node|
            return [each_first_node, each_next_node] if component_precedes?(each_first_node, each_next_node)
          end
        end
        nil
      end

      # If first node does not precede next_node, sets appropriate instance variables for reporting.
      def component_precedes?(first_node, next_node)
        return false if line_number(first_node) < line_number(next_node)

        @offensive_node = first_node
        true
      end

      # Check if negation is present in the given node.
      def expression_negated?(node)
        return false unless node.parent&.send_type?
        return false unless node.parent.method_name.equal?(:!)

        offending_node(node.parent)
      end

      # Returns the array of arguments of the method_node.
      def parameters(method_node)
        method_node.arguments if method_node.send_type? || method_node.block_type?
      end

      # Returns true if the given parameters are present in method call
      # and sets the method call as the offending node.
      # Params can be string, symbol, array, hash, matching regex.
      def parameters_passed?(method_node, params)
        method_params = parameters(method_node)
        @offensive_node = method_node
        params.all? do |given_param|
          method_params.any? do |method_param|
            if given_param.instance_of?(Regexp)
              regex_match_group(method_param, given_param)
            else
              node_equals?(method_param, given_param)
            end
          end
        end
      end

      # Returns the ending position of the node in source code.
      def end_column(node)
        node.source_range.end_pos
      end

      # Returns the class node's name, or nil if not a class node.
      def class_name(node)
        @offensive_node = node
        node.const_name
      end

      # Returns the method name for a def node.
      def method_name(node)
        node.children[0] if node.def_type?
      end

      # Returns the node size in the source code.
      def size(node)
        node.source_range.size
      end

      # Returns the block length of the block node.
      def block_size(block)
        block.loc.end.line - block.loc.begin.line
      end

      # Returns printable component name.
      def format_component(component_node)
        return component_node.method_name if component_node.send_type? || component_node.block_type?

        method_name(component_node) if component_node.def_type?
      end
    end
  end
end
