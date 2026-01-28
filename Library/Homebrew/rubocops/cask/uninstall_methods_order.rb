# typed: strict
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    module Cask
      # This cop checks for the correct order of methods within the
      # 'uninstall' and 'zap' stanzas and validates related metadata.
      class UninstallMethodsOrder < Base
        extend AutoCorrector
        include HelperFunctions

        MSG = T.let("`%<method>s` method out of order", String)

        # These keys are ignored when checking method order.
        # Mirrors AbstractUninstall::METADATA_KEYS.
        METADATA_KEYS = T.let(
          [:on_upgrade].freeze,
          T::Array[Symbol],
        )

        USELESS_METADATA_MSG = T.let(
          "`on_upgrade` has no effect without matching `uninstall quit:` or `uninstall signal:` directives",
          String,
        )

        PARTIAL_METADATA_MSG = T.let(
          "`on_upgrade` lists %<symbols>s without matching `uninstall` directives",
          String,
        )

        sig { params(node: AST::SendNode).void }
        def on_send(node)
          return unless [:zap, :uninstall].include?(node.method_name)

          hash_node = node.arguments.first
          return if hash_node.nil? || (!hash_node.is_a?(AST::Node) && !hash_node.hash_type?)

          comments = processed_source.comments

          check_ordering(hash_node, comments)
          check_metadata(hash_node, comments)
        end

        private

        sig {
          params(
            hash_node: AST::HashNode,
            comments:  T::Array[Parser::Source::Comment],
          ).void
        }
        def check_ordering(hash_node, comments)
          method_nodes = hash_node.pairs.map(&:key).reject do |method|
            name = method.children.first
            METADATA_KEYS.include?(name)
          end

          expected_order = method_nodes.sort_by { |method| method_order_index(method) }
          method_nodes.each_with_index do |method, index|
            next if method == expected_order[index]

            report_and_correct_ordering_offense(method, hash_node, expected_order, comments)
          end
        end

        sig {
          params(method:         AST::Node,
                 hash_node:      AST::HashNode,
                 expected_order: T::Array[AST::Node],
                 comments:       T::Array[Parser::Source::Comment]).void
        }
        def report_and_correct_ordering_offense(method, hash_node, expected_order, comments)
          add_offense(method, message: format(MSG, method: method.children.first)) do |corrector|
            ordered_pairs = expected_order.map do |expected_method|
              hash_node.pairs.find { |pair| pair.key == expected_method }
            end

            indentation = " " * (start_column(method) - line_start_column(method))
            new_code = build_uninstall_body(ordered_pairs, comments, indentation)

            corrector.replace(hash_node.source_range, new_code)
          end
        end

        sig {
          params(
            hash_node: AST::HashNode,
            comments:  T::Array[Parser::Source::Comment],
          ).void
        }
        def check_metadata(hash_node, comments)
          on_upgrade_pair = hash_node.pairs.find { |p| p.key.value == :on_upgrade }
          return unless on_upgrade_pair

          requested = on_upgrade_symbols(on_upgrade_pair.value)
          return report_fully_invalid_metadata(on_upgrade_pair) if requested.empty?

          available = []
          available << :quit   if hash_node.pairs.any? { |p| p.key.value == :quit }
          available << :signal if hash_node.pairs.any? { |p| p.key.value == :signal }

          valid_syms   = requested & available
          invalid_syms = requested - available

          if valid_syms.empty?
            remaining_pairs = hash_node.pairs.reject { |p| p == on_upgrade_pair }
            report_and_correct_useless_metadata(hash_node, on_upgrade_pair, remaining_pairs, comments)
          elsif invalid_syms.any?
            report_partially_invalid_metadata(on_upgrade_pair.value, invalid_syms)
          end
        end

        sig { params(on_upgrade_pair: AST::PairNode).void }
        def report_fully_invalid_metadata(on_upgrade_pair)
          add_offense(on_upgrade_pair.value,
                      message: "`on_upgrade` value must be :quit, :signal, or an array of those symbols")
        end

        sig {
          params(
            hash_node:       AST::HashNode,
            on_upgrade_pair: AST::PairNode,
            remaining_pairs: T::Array[AST::PairNode],
            comments:        T::Array[Parser::Source::Comment],
          ).void
        }
        def report_and_correct_useless_metadata(
          hash_node,
          on_upgrade_pair,
          remaining_pairs,
          comments
        )
          if remaining_pairs.empty?
            # Only on_upgrade is present: report but do not attempt autocorrect
            # to avoid generating an empty uninstall hash or removing the stanza.
            add_offense(on_upgrade_pair.key, message: USELESS_METADATA_MSG)
            return
          end

          add_offense(on_upgrade_pair.key, message: USELESS_METADATA_MSG) do |corrector|
            first_pair = T.must(remaining_pairs.first)
            indentation = " " * (start_column(first_pair.key) - line_start_column(first_pair.key))

            new_code = build_uninstall_body(remaining_pairs, comments, indentation)
            corrector.replace(hash_node.source_range, new_code)
          end
        end

        sig {
          params(value_node: AST::Node, invalid_syms: T::Array[Symbol]).void
        }
        def report_partially_invalid_metadata(value_node, invalid_syms)
          symbols_str = invalid_syms.map { |s| ":#{s}" }.join(", ")
          add_offense(value_node,
                      message: format(PARTIAL_METADATA_MSG, symbols: symbols_str))
        end

        sig {
          params(
            pairs:       T::Array[AST::PairNode],
            comments:    T::Array[Parser::Source::Comment],
            indentation: String,
          ).returns(String)
        }
        def build_uninstall_body(pairs, comments, indentation)
          pairs.map do |pair|
            source = pair.source

            # Find and attach a comment on the same line as the pair, if any
            inline_comment = comments.find do |comment|
              comment.location.line == pair.loc.line &&
                comment.location.column > pair.loc.column
            end

            inline_comment ? "#{source} #{inline_comment.text}" : source
          end.join(",\n#{indentation}")
        end

        sig { params(value_node: AST::Node).returns(T::Array[Symbol]) }
        def on_upgrade_symbols(value_node)
          if value_node.sym_type?
            [T.cast(value_node, AST::SymbolNode).value]
          elsif value_node.array_type?
            value_node.children.select(&:sym_type?).map do |child|
              T.cast(child, AST::SymbolNode).value
            end
          else
            []
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
