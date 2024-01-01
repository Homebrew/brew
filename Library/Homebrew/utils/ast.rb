# typed: strict
# frozen_string_literal: true

require "ast_constants"
require "rubocop-ast"

module Utils
  # Helper functions for editing Ruby files.
  #
  # @api private
  module AST
    Node = RuboCop::AST::Node
    SendNode = RuboCop::AST::SendNode
    BlockNode = RuboCop::AST::BlockNode
    ProcessedSource = RuboCop::AST::ProcessedSource
    TreeRewriter = Parser::Source::TreeRewriter

    module_function

    sig { params(body_node: Node).returns(T::Array[Node]) }
    def body_children(body_node)
      if body_node.blank?
        []
      elsif body_node.begin_type?
        body_node.children.compact
      else
        [body_node]
      end
    end

    sig { params(name: Symbol, value: T.any(Numeric, String, Symbol), indent: T.nilable(Integer)).returns(String) }
    def stanza_text(name, value, indent: nil)
      text = if value.is_a?(String)
        _, node = process_source(value)
        value if (node.is_a?(SendNode) || node.is_a?(BlockNode)) && node.method_name == name
      end
      text ||= "#{name} #{value.inspect}"
      text = text.indent(indent) if indent && !text.match?(/\A\n* +/)
      text
    end

    sig { params(source: String).returns([ProcessedSource, Node]) }
    def process_source(source)
      ruby_version = Version.new(HOMEBREW_REQUIRED_RUBY_VERSION).major_minor.to_f
      processed_source = ProcessedSource.new(source, ruby_version)
      root_node = processed_source.ast
      [processed_source, root_node]
    end

    sig {
      params(
        component_name: Symbol,
        component_type: Symbol,
        target_name:    Symbol,
        target_type:    T.nilable(Symbol),
      ).returns(T::Boolean)
    }
    def component_match?(component_name:, component_type:, target_name:, target_type: nil)
      component_name == target_name && (target_type.nil? || component_type == target_type)
    end

    sig { params(node: Node, name: Symbol, type: T.nilable(Symbol)).returns(T::Boolean) }
    def call_node_match?(node, name:, type: nil)
      node_type = case node
      when SendNode then :method_call
      when BlockNode then :block_call
      else return false
      end

      component_match?(component_name: node.method_name,
                       component_type: node_type,
                       target_name:    name,
                       target_type:    type)
    end

    # Helper class for editing formulae.
    #
    # @api private
    class FormulaAST
      extend Forwardable
      include AST

      delegate process: :tree_rewriter

      sig { params(formula_contents: String).void }
      def initialize(formula_contents)
        @formula_contents = formula_contents
        processed_source, children = process_formula
        @processed_source = T.let(processed_source, ProcessedSource)
        @children = T.let(children, T::Array[Node])
        @tree_rewriter = T.let(TreeRewriter.new(processed_source.buffer), TreeRewriter)
      end

      sig { returns(T.nilable(Node)) }
      def bottle_block
        stanza(:bottle, type: :block_call)
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).returns(T.nilable(Node)) }
      def stanza(name, type: nil)
        children.find { |child| call_node_match?(child, name: name, type: type) }
      end

      sig { params(bottle_output: String).void }
      def replace_bottle_block(bottle_output)
        replace_stanza(:bottle, bottle_output.chomp, type: :block_call)
      end

      sig { params(bottle_output: String).void }
      def add_bottle_block(bottle_output)
        add_stanza(:bottle, "\n#{bottle_output.chomp}", type: :block_call)
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).void }
      def remove_stanza(name, type: nil)
        stanza_node = stanza(name, type: type)
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        # stanza is probably followed by a newline character
        # try to delete it if so
        stanza_range = stanza_node.source_range
        trailing_range = stanza_range.with(begin_pos: stanza_range.end_pos,
                                           end_pos:   stanza_range.end_pos + 1)
        if trailing_range.source.chomp.empty?
          stanza_range = stanza_range.adjust(end_pos: 1)

          # stanza_node is probably indented
          # since a trailing newline has been removed,
          # try to delete leading whitespace on line
          leading_range = stanza_range.with(begin_pos: stanza_range.begin_pos - stanza_range.column,
                                            end_pos:   stanza_range.begin_pos)
          if leading_range.source.strip.empty?
            stanza_range = stanza_range.adjust(begin_pos: -stanza_range.column)

            # if the stanza was preceded by a blank line, it should be removed
            # that is, if the two previous characters are newlines,
            # then delete one of them
            leading_range = stanza_range.with(begin_pos: stanza_range.begin_pos - 2,
                                              end_pos:   stanza_range.begin_pos)
            stanza_range = stanza_range.adjust(begin_pos: -1) if leading_range.source.chomp.chomp.empty?
          end
        end

        tree_rewriter.remove(stanza_range)
      end

      sig { params(name: Symbol, replacement: T.any(Numeric, String, Symbol), type: T.nilable(Symbol)).void }
      def replace_stanza(name, replacement, type: nil)
        stanza_node = stanza(name, type: type)
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        tree_rewriter.replace(stanza_node.source_range, stanza_text(name, replacement, indent: 2).lstrip)
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol), type: T.nilable(Symbol)).void }
      def add_stanza(name, value, type: nil)
        preceding_component = if children.length > 1
          children.reduce do |previous_child, current_child|
            if formula_component_before_target?(current_child,
                                                target_name: name,
                                                target_type: type)
              next current_child
            else
              break previous_child
            end
          end
        else
          children.first
        end
        preceding_component = preceding_component.last_argument if preceding_component.is_a?(SendNode)

        preceding_expr = preceding_component.location.expression
        processed_source.comments.each do |comment|
          comment_expr = comment.location.expression
          distance = comment_expr.first_line - preceding_expr.first_line
          case distance
          when 0
            if comment_expr.last_line > preceding_expr.last_line ||
               comment_expr.end_pos > preceding_expr.end_pos
              preceding_expr = comment_expr
            end
          when 1
            preceding_expr = comment_expr
          end
        end

        tree_rewriter.insert_after(preceding_expr, "\n#{stanza_text(name, value, indent: 2)}")
      end

      private

      sig { returns(String) }
      attr_reader :formula_contents

      sig { returns(ProcessedSource) }
      attr_reader :processed_source

      sig { returns(T::Array[Node]) }
      attr_reader :children

      sig { returns(TreeRewriter) }
      attr_reader :tree_rewriter

      sig { returns([ProcessedSource, T::Array[Node]]) }
      def process_formula
        processed_source, root_node = process_source(formula_contents)

        class_node = root_node if root_node.class_type?
        if root_node.begin_type?
          nodes = root_node.children.select(&:class_type?)
          class_node = if nodes.count > 1
            nodes.find { |n| n.parent_class&.const_name == "Formula" }
          else
            nodes.first
          end
        end

        raise "Could not find formula class!" if class_node.nil?

        children = body_children(class_node.body)
        raise "Formula class is empty!" if children.empty?

        [processed_source, children]
      end

      sig { params(node: Node, target_name: Symbol, target_type: T.nilable(Symbol)).returns(T::Boolean) }
      def formula_component_before_target?(node, target_name:, target_type: nil)
        FORMULA_COMPONENT_PRECEDENCE_LIST.each do |components|
          return false if components.any? do |component|
            component_match?(component_name: component[:name],
                             component_type: component[:type],
                             target_name:    target_name,
                             target_type:    target_type)
          end
          return true if components.any? do |component|
            call_node_match?(node, name: component[:name], type: component[:type])
          end
        end

        false
      end
    end
  end
end
