# typed: strict
# frozen_string_literal: true

require "ast_constants"
require "rubocop-ast"

module Utils
  # Helper functions for editing Ruby files.
  module AST
    Node = RuboCop::AST::Node
    SendNode = RuboCop::AST::SendNode
    BlockNode = RuboCop::AST::BlockNode
    DefNode = RuboCop::AST::DefNode
    ProcessedSource = RuboCop::AST::ProcessedSource
    TreeRewriter = Parser::Source::TreeRewriter

    module_function

    sig { params(body_node: T.nilable(Node)).returns(T::Array[Node]) }
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
      text = text.gsub(/^(?!$)/, " " * indent) if indent && !text.match?(/\A\n* +/)
      text
    end

    sig { params(value: T.any(Numeric, String, Symbol)).returns(String) }
    def ruby_literal(value)
      value.inspect
    end

    sig { params(node: Node).returns(T.untyped) }
    def literal_value(node)
      return node.str_content if node.str_type?
      return T.unsafe(node).value if node.sym_type? || node.numeric_type?

      nil
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
        stanzas(name, type:).first
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).returns(T::Array[Node]) }
      def stanzas(name, type: nil)
        matching_stanzas(children, name, type:)
      end

      sig { params(name: String).returns(BlockNode) }
      def resource(name)
        possible_resource_stanzas = if stanza(:stable, type: :block_call).present?
          # Needed resource block may be either in `stable` or in formula body, hence appending
          # `children` nodes
          stable_children + children
        else
          children
        end
        resource = matching_stanzas(possible_resource_stanzas, :resource, type: :block_call).find do |resource_node|
          T.cast(resource_node, BlockNode).send_node.first_argument&.str_content == name
        end
        raise "Could not find resource '#{name}' block!" if resource.blank?

        T.cast(resource, BlockNode)
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stable_stanza_value(name, value)
        replace_stanza_value(stable_stanza(name), value)
      end

      sig { params(name: Symbol, key: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stable_stanza_hash_value(name, key, value)
        replace_stanza_hash_value(stable_stanza(name), key, value)
      end

      sig { params(name: Symbol).returns(T::Boolean) }
      def stable_stanza?(name)
        matching_stanzas(stable_children, name).present?
      end

      sig { params(name: Symbol).void }
      def remove_stable_stanza(name)
        remove_stanza_node(stable_stanza(name))
      end

      sig { params(name: Symbol).void }
      def remove_stable_stanzas(name)
        stanza_nodes = matching_stanzas(stable_children, name)
        raise "Could not find '#{name}' stanza!" if stanza_nodes.empty?

        stanza_nodes.each { |stanza_node| remove_stanza_node(stanza_node) }
      end

      sig {
        params(
          after_name:  Symbol,
          new_stanzas: T::Array[[Symbol, T.any(Numeric, String, Symbol)]],
        ).void
      }
      def add_stable_stanzas_after(after_name, new_stanzas)
        add_stanzas_after(after_name, new_stanzas, parent: stanza(:stable, type: :block_call))
      end

      sig {
        params(
          resource_name: String,
          name:          Symbol,
          value:         T.any(Numeric, String, Symbol),
          old_value:     T.nilable(T.any(Numeric, String, Symbol)),
        ).void
      }
      def replace_resource_stanza_value(resource_name, name, value, old_value: nil)
        replace_stanza_value(resource_stanza(resource_name, name, old_value:), value)
      end

      sig { params(resource_name: String, name: Symbol).returns(T::Boolean) }
      def resource_stanza?(resource_name, name)
        matching_stanzas(body_children(resource(resource_name).body), name).present?
      end

      sig {
        params(
          after_name:  Symbol,
          new_stanzas: T::Array[[Symbol, T.any(Numeric, String, Symbol)]],
          parent:      T.nilable(Node),
        ).void
      }
      def add_stanzas_after(after_name, new_stanzas, parent: nil)
        return if new_stanzas.empty?

        preceding_component = if parent
          matching_stanzas(body_children(T.cast(parent, BlockNode).body), after_name).last
        else
          stanza(after_name)
        end
        raise "Could not find '#{after_name}' stanza!" if preceding_component.blank?

        preceding_expr = source_range_with_trailing_comments(preceding_component)
        text = new_stanzas.map do |stanza_name, value|
          "\n#{stanza_text(stanza_name, value, indent: preceding_component.source_range.column)}"
        end.join
        tree_rewriter.insert_after(preceding_expr, text)
      end

      sig {
        params(
          resource_section:   String,
          replace_existing:   T::Boolean,
          preserve_livecheck: T::Boolean,
        ).returns(T.nilable(Symbol))
      }
      def replace_resource_stanzas(resource_section, replace_existing: true, preserve_livecheck: false)
        resource_section = resource_section.gsub(/^(?!$)/, "  ") unless resource_section.match?(/\A\n* +/)

        if replace_existing
          groups = resource_stanza_groups(preserve_livecheck:)
          return :multiple_groups if groups.length > 1

          if (group = groups.first)
            tree_rewriter.replace(resource_stanza_group_range(group), resource_section)
            return
          end
        end

        install_node = method_definition(:install)
        raise "Could not find 'install' method!" if install_node.blank?

        tree_rewriter.insert_before(whole_line_range(install_node.source_range), resource_section)
        nil
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
        stanza_node = stanza(name, type:)
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        remove_stanza_node(stanza_node)
      end

      sig { params(name: Symbol, replacement: T.any(Numeric, String, Symbol), type: T.nilable(Symbol)).void }
      def replace_stanza(name, replacement, type: nil)
        stanza_node = stanza(name, type:)
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

      sig { params(nodes: T::Array[Node], name: Symbol, type: T.nilable(Symbol)).returns(T::Array[Node]) }
      def matching_stanzas(nodes, name, type: nil)
        nodes.select { |child| call_node_match?(child, name:, type:) }
      end

      sig { params(name: Symbol).returns(Node) }
      def stable_stanza(name)
        stanza_node = matching_stanzas(stable_children, name).first
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        stanza_node
      end

      sig {
        params(
          resource_name: String,
          name:          Symbol,
          old_value:     T.nilable(T.any(Numeric, String, Symbol)),
        ).returns(Node)
      }
      def resource_stanza(resource_name, name, old_value: nil)
        stanza_node = matching_stanzas(body_children(resource(resource_name).body), name).find do |node|
          old_value.nil? || literal_value(T.cast(node, T.any(SendNode, BlockNode)).first_argument) == old_value
        end
        raise "Could not find '#{name}' stanza in resource '#{resource_name}'!" if stanza_node.blank?

        stanza_node
      end

      sig { returns(T::Array[Node]) }
      def stable_children
        if (stable_node = stanza(:stable, type: :block_call))
          body_children(T.cast(stable_node, BlockNode).body)
        else
          children
        end
      end

      sig { params(stanza_node: Node, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_value(stanza_node, value)
        stanza_node = T.cast(stanza_node, T.any(SendNode, BlockNode))
        argument = stanza_node.first_argument
        raise "Could not find '#{stanza_node.method_name}' stanza value!" if argument.blank?

        tree_rewriter.replace(argument.source_range, ruby_literal(value))
      end

      sig { params(stanza_node: Node, key: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_hash_value(stanza_node, key, value)
        stanza_node = T.cast(stanza_node, T.any(SendNode, BlockNode))
        pair = stanza_node.arguments.grep(RuboCop::AST::HashNode).flat_map(&:pairs).find do |hash_pair|
          literal_value(hash_pair.key) == key
        end
        raise "Could not find '#{key}' value in '#{stanza_node.method_name}' stanza!" if pair.blank?

        tree_rewriter.replace(pair.value.source_range, ruby_literal(value))
      end

      sig { params(stanza_node: Node).void }
      def remove_stanza_node(stanza_node)
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

      sig { params(node: T.any(Node, Parser::Source::Range)).returns(Parser::Source::Range) }
      def source_range_with_trailing_comments(node)
        preceding_expr = node.is_a?(Parser::Source::Range) ? node : node.location.expression
        processed_source.comments.each do |comment|
          comment_expr = comment.location.expression
          distance = comment_expr.first_line - preceding_expr.last_line
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
        preceding_expr
      end

      sig { params(name: Symbol).returns(T.nilable(DefNode)) }
      def method_definition(name)
        T.cast(
          children.find { |child| child.def_type? && T.cast(child, DefNode).method_name == name },
          T.nilable(DefNode),
        )
      end

      sig { params(preserve_livecheck: T::Boolean).returns(T::Array[T::Array[BlockNode]]) }
      def resource_stanza_groups(preserve_livecheck: false)
        test_node = stanza(:test, type: :block_call)
        resource_nodes = stanzas(:resource, type: :block_call).filter_map do |node|
          node = T.cast(node, BlockNode)
          next if test_node.present? && node.source_range.begin_pos > test_node.source_range.begin_pos

          next if preserve_livecheck &&
                  matching_stanzas(body_children(node.body), :livecheck, type: :block_call).present?

          node
        end

        groups = T.let([], T::Array[T::Array[BlockNode]])
        resource_nodes.each do |resource_node|
          previous_group = groups.last
          if previous_group.nil? || !resource_stanzas_contiguous?(previous_group.fetch(-1), resource_node)
            groups << [resource_node]
          else
            previous_group << resource_node
          end
        end
        groups
      end

      sig { params(previous_node: BlockNode, current_node: BlockNode).returns(T::Boolean) }
      def resource_stanzas_contiguous?(previous_node, current_node)
        previous_end = whole_line_range(previous_node.source_range).end_pos
        current_start = current_node.source_range.begin_pos - current_node.source_range.column
        formula_contents[previous_end...current_start].to_s.lines.all? do |line|
          line.strip.empty? || line.strip.start_with?("# RESOURCE-ERROR:")
        end
      end

      sig { params(group: T::Array[BlockNode]).returns(Parser::Source::Range) }
      def resource_stanza_group_range(group)
        first_range = source_range_with_leading_resource_error_comments(group.fetch(0).source_range)
        last_range = whole_line_range(group.fetch(-1).source_range, include_following_blank_lines: true)
        first_range.with(
          begin_pos: first_range.begin_pos - first_range.column,
          end_pos:   last_range.end_pos,
        )
      end

      sig { params(range: Parser::Source::Range).returns(Parser::Source::Range) }
      def source_range_with_leading_resource_error_comments(range)
        loop do
          line_start = range.begin_pos - range.column
          previous_comments = processed_source.comments.select do |comment|
            comment.location.expression.end_pos <= line_start &&
              comment.text.start_with?("# RESOURCE-ERROR:")
          end
          previous_comment = previous_comments.max_by { |comment| comment.location.expression.end_pos }
          break if previous_comment.blank?

          comment_range = previous_comment.location.expression
          break unless formula_contents[comment_range.end_pos...line_start].to_s.lines.all? do |line|
            line.strip.empty?
          end

          range = T.cast(range.with(begin_pos: comment_range.begin_pos), Parser::Source::Range)
        end
        range
      end

      sig {
        params(
          range:                         Parser::Source::Range,
          include_following_blank_lines: T::Boolean,
        ).returns(Parser::Source::Range)
      }
      def whole_line_range(range, include_following_blank_lines: false)
        begin_pos = range.begin_pos - range.column
        end_pos = line_end_pos(range.end_pos)
        if include_following_blank_lines
          while end_pos < formula_contents.length
            next_line_end = line_end_pos(end_pos)
            break unless formula_contents[end_pos...next_line_end].to_s.strip.empty?

            end_pos = next_line_end
          end
        end
        range.with(begin_pos:, end_pos:)
      end

      sig { params(position: Integer).returns(Integer) }
      def line_end_pos(position)
        newline_pos = formula_contents.index("\n", position)
        newline_pos ? newline_pos + 1 : formula_contents.length
      end

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
                             target_name:,
                             target_type:)
          end
          return true if components.any? do |component|
            call_node_match?(node, name: component[:name], type: component[:type])
          end
        end

        false
      end
    end

    # Helper class for editing casks.
    class CaskAST
      include AST

      sig { params(cask_contents: String).void }
      def initialize(cask_contents)
        @cask_contents = cask_contents
        processed_source, cask_block = process_cask
        @processed_source = T.let(processed_source, ProcessedSource)
        @cask_block = T.let(cask_block, BlockNode)
        @tree_rewriter = T.let(TreeRewriter.new(processed_source.buffer), TreeRewriter)
      end

      sig { returns(String) }
      def process
        tree_rewriter.process
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_first_stanza_value(name, value)
        stanza_node = stanzas(name).first
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        replace_stanza_argument(stanza_node, value)
      end

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T::Boolean) }
      def stanza?(name, within: nil)
        stanzas(name, within:).present?
      end

      sig { params(name: Symbol, within: Symbol).returns(T::Boolean) }
      def stanza_anywhere?(name, within:)
        cask_block.each_node(:block).any? do |node|
          block_node = T.cast(node, BlockNode)
          next false if block_node.method_name != within || block_node.receiver.present?

          block_node.each_node(:send).any? do |send_node|
            send_node.method_name == name && send_node.receiver.nil? && send_node.first_argument.present?
          end
        end
      end

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T.untyped) }
      def first_stanza_value(name, within: nil)
        stanza_node = stanzas(name, within:).first
        return if stanza_node.blank?

        literal_value(stanza_node.first_argument)
      end

      sig {
        params(
          name:      Symbol,
          old_value: T.any(Numeric, String, Symbol),
          new_value: T.any(Numeric, String, Symbol),
          within:    T.nilable(Symbol),
        ).returns(Integer)
      }
      def replace_stanza_value(name, old_value, new_value, within: nil)
        replacement_count = T.let(0, Integer)
        stanzas(name, within:).each do |stanza_node|
          if literal_value(stanza_node.first_argument) == old_value
            replace_stanza_argument(stanza_node, new_value)
            replacement_count += 1
          end

          stanza_node.arguments.grep(RuboCop::AST::HashNode).each do |hash_node|
            hash_node.pairs.each do |pair|
              next if literal_value(pair.value) != old_value

              tree_rewriter.replace(pair.value.source_range, ruby_literal(new_value))
              replacement_count += 1
            end
          end
        end

        replacement_count
      end

      sig { params(name: Symbol, old_value: T.any(Numeric, String, Symbol)).void }
      def replace_root_stanza_with_arch_blocks(name, old_value)
        stanza_node = top_level_stanzas(name).find do |node|
          literal_value(node.first_argument) == old_value
        end
        return if stanza_node.blank?

        indent = " " * stanza_node.source_range.column
        replacement = <<~EOS
          #{indent}on_arm do
          #{indent}  #{name} #{ruby_literal(old_value)}
          #{indent}end
          #{indent}on_intel do
          #{indent}  #{name} #{ruby_literal(old_value)}
          #{indent}end
        EOS
        tree_rewriter.replace(whole_line_range(stanza_node.source_range), replacement)
      end

      sig { returns(T::Boolean) }
      def depends_on_macos?
        stanzas(:depends_on).any? do |stanza_node|
          stanza_node.arguments.any? do |argument|
            literal_value(argument) == :macos ||
              (argument.hash_type? && T.cast(argument, RuboCop::AST::HashNode).pairs.any? do |pair|
                literal_value(pair.key) == :macos
              end)
          end
        end
      end

      private

      sig { returns(String) }
      attr_reader :cask_contents

      sig { returns(ProcessedSource) }
      attr_reader :processed_source

      sig { returns(BlockNode) }
      attr_reader :cask_block

      sig { returns(TreeRewriter) }
      attr_reader :tree_rewriter

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T::Array[SendNode]) }
      def stanzas(name, within: nil)
        if within == :root
          nodes = body_children(cask_block.body).grep(SendNode)
        elsif within
          blocks = on_system_blocks(within)
          return [] if blocks.blank?

          nodes = blocks.flat_map { |block| body_children(block.body).grep(SendNode) }
        else
          nodes = cask_block.each_node(:send)
        end

        nodes.select do |node|
          node.method_name == name && node.receiver.nil? && node.first_argument.present?
        end
      end

      sig { params(name: Symbol).returns(T::Array[SendNode]) }
      def top_level_stanzas(name)
        body_children(cask_block.body).grep(SendNode).select do |node|
          node.method_name == name && node.receiver.nil? && node.first_argument.present?
        end
      end

      sig { params(name: Symbol).returns(T::Array[BlockNode]) }
      def on_system_blocks(name)
        body_children(cask_block.body).grep(BlockNode).select do |node|
          node.method_name == name && node.receiver.nil?
        end
      end

      sig { params(stanza_node: SendNode, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_argument(stanza_node, value)
        argument = stanza_node.first_argument
        raise "Could not find '#{stanza_node.method_name}' stanza value!" if argument.blank?

        tree_rewriter.replace(argument.source_range, ruby_literal(value))
      end

      sig { params(range: Parser::Source::Range).returns(Parser::Source::Range) }
      def whole_line_range(range)
        range.with(
          begin_pos: range.begin_pos - range.column,
          end_pos:   line_end_pos(range.end_pos),
        )
      end

      sig { params(position: Integer).returns(Integer) }
      def line_end_pos(position)
        newline_pos = cask_contents.index("\n", position)
        newline_pos ? newline_pos + 1 : cask_contents.length
      end

      sig { returns([ProcessedSource, BlockNode]) }
      def process_cask
        processed_source, root_node = process_source(cask_contents)
        cask_block = if root_node.block_type? && T.cast(root_node, BlockNode).method_name == :cask
          T.cast(root_node, BlockNode)
        elsif root_node.begin_type?
          root_node.children.find { |node| node.block_type? && node.method_name == :cask }
        end

        raise "Could not find cask block!" if cask_block.nil?

        [processed_source, T.cast(cask_block, BlockNode)]
      end
    end
  end
end
