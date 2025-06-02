# typed: strict
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    module Cask
      # This cop checks for the correct order of methods within the 'uninstall' and 'zap' stanzas.
      class UninstallMethodsOrder < Base
        extend AutoCorrector
        include HelperFunctions

        MSG = T.let("`%<method>s` method out of order", String)

        sig { params(node: AST::SendNode).void }
        def on_send(node)
          return unless [:zap, :uninstall].include?(node.method_name)

          hash_node = node.arguments.first
          return if hash_node.nil? || (!hash_node.is_a?(AST::Node) && !hash_node.hash_type?)

          method_nodes = hash_node.pairs.map(&:key)
          expected_order = method_nodes.sort_by { |method| method_order_index(method) }
          comments = processed_source.comments

          method_nodes.each_with_index do |method, index|
            next if method == expected_order[index]

            report_and_correct_offense(method, hash_node, expected_order, comments)
          end
        end

        sig {
          params(method:         AST::Node,
                 hash_node:      AST::HashNode,
                 expected_order: T::Array[AST::Node],
                 comments:       T::Array[Parser::Source::Comment]).void
        }
        def report_and_correct_offense(method, hash_node, expected_order, comments)
          add_offense(method, message: format(MSG, method: method.children.first)) do |corrector|
            indentation = " " * (start_column(method) - line_start_column(method))
            new_code = expected_order.map do |expected_method|
              method_pair = hash_node.pairs.find { |pair| pair.key == expected_method }
              source = method_pair.source

              # Find and attach a comment on the same line as the method_pair, if any
              inline_comment = comments.find do |comment|
                comment.location.line == method_pair.loc.line && comment.location.column > method_pair.loc.column
              end
              inline_comment ? "#{source} #{inline_comment.text}" : source
            end.join(",\n#{indentation}")
            corrector.replace(hash_node.source_range, new_code)
          end
        end

        sig { params(method_node: AST::SymbolNode).returns(Integer) }
        def method_order_index(method_node)
          method_name = method_node.children.first
          RuboCop::Cask::Constants::UNINSTALL_METHODS_ORDER.index(method_name) || -1
        end
      end
    end
  end
end
