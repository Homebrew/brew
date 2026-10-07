# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that {Formula} is used as superclass.
      class ClassName < FormulaCop
        extend AutoCorrector

        DEPRECATED_CLASSES = %w[
          GithubGistFormula
          ScriptFileFormula
          AmazonWebServicesFormula
        ].freeze

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          parent_class_node = formula_nodes.parent_class_node

          parent_class = class_name(parent_class_node)
          return unless DEPRECATED_CLASSES.include?(parent_class)

          problem "`#{parent_class}` is deprecated, use `Formula` instead" do |corrector|
            corrector.replace(parent_class_node.source_range, "Formula")
          end
        end
      end

      # This cop makes sure that a `test` block exists and contains a real test.
      class Test < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node
          test = find_block(body_node, :test)
          if test.nil?
            return if find_node_method_by_name(body_node, :disable!)

            offending_node(formula_nodes.class_node) if body_node.nil?
            problem "A `test do` test block should be added"
            return
          end

          if test.body.nil?
            problem "`test do` should not be empty"
            return
          end

          problem "`test do` should contain a real test" if test.body.single_line? && test.body.source.to_s == "true"

          test_calls(test) do |node, params|
            p1, p2 = params
            if (match = string_content(p1).match(%r{(/usr/local/(s?bin))}))
              offending_node(p1)
              problem "Use `\#{#{match[2]}}` instead of `#{match[1]}` in `#{node}`" do |corrector|
                corrector.replace(p1.source_range, p1.source.sub(match[1], "\#{#{match[2]}}"))
              end
            end

            if node == :shell_output && node_equals?(p2, 0)
              offending_node(p2)
              problem "Passing 0 to `shell_output` is redundant" do |corrector|
                corrector.remove(range_with_surrounding_comma(range_with_surrounding_space(range: p2.source_range,
                                                                                           side:  :left)))
              end
            end
          end
        end

        def_node_search :test_calls, <<~EOS
          (send nil? ${:system :shell_output :pipe_output} $...)
        EOS
      end

      # This cop moves resource declarations outside test blocks for prefetching.
      class TestResource < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if formula_tap != "homebrew-core"

          test = find_block(formula_nodes.body_node, :test)
          return unless test

          find_all_blocks(test, :resource).reverse_each do |resource|
            next if resource.send_node.receiver

            add_offense(
              resource.send_node,
              message: 'Declare test resources outside `test do` using `resource "name", :test do`.',
            ) do |corrector|
              next if find_every_method_call_by_name(formula_nodes.body_node, :resources).any?

              name = resource.send_node.first_argument
              next unless name&.str_type?
              next if resource.parent != test && resource.parent != test.body
              next if resource.single_line? || test.single_line?
              if !resource.send_node.arguments.one? &&
                 (resource.send_node.arguments.size != 2 || resource.send_node.last_argument&.source != ":test")
                next
              end

              # Moving runtime expressions or multiline strings can change their meaning.
              next if resource.each_descendant.any? do |node|
                next false if node.true_type? || node.false_type?

                if node.is_a?(RuboCop::AST::SendNode)
                  node.receiver || ![:resource, :url, :sha256, :mirror, :version, :patch].include?(node.method_name)
                else
                  ![:block, :args, :begin, :str, :sym, :int, :nil, :hash, :pair, :array].include?(node.type) ||
                  (node.is_a?(RuboCop::AST::StrNode) && (node.multiline? || node.heredoc?))
                end
              end

              range = range_with_comments_and_lines(resource)
              next unless resource.source_range.source_line[0...resource.source_range.column].strip.empty?

              trailing = range.source_buffer.source[resource.source_range.end_pos...range.end_pos].strip
              next if trailing.present? && !trailing.start_with?("#")

              source = range.source
              if resource.send_node.arguments.one?
                source.insert(name.source_range.end_pos - range.begin_pos,
                              ", :test")
              end
              source = source.gsub(/^ {#{resource.source_range.column - test.source_range.column}}/, "")
              corrector.insert_before(range_with_comments_and_lines(test), "#{source}\n")
              range = range.adjust(end_pos: 1) if range.source_buffer.source[range.end_pos] == "\n"
              corrector.remove(range)
            end
          end
        end
      end
    end
  end
end
