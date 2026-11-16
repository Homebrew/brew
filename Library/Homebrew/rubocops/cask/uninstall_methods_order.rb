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

        MSG = "`%<method>s` method out of order"

        # These keys are ignored when checking method order.
        # Mirrors AbstractUninstall::METADATA_KEYS.
        METADATA_KEYS = [:on_upgrade].freeze

        USELESS_METADATA_MSG =
          "`on_upgrade` has no effect without matching `uninstall signal:` directive"

        PARTIAL_METADATA_MSG = "`on_upgrade` lists %<symbols>s without matching `uninstall` directives"

        sig { params(node: AST::SendNode).void }
        def on_send(node)
          return unless [:zap, :uninstall].include?(node.method_name)

          hash_node = node.arguments.first
          return unless hash_node.is_a?(AST::HashNode)

          comments = processed_source.comments

          method_nodes = hash_node.pairs.map(&:key).reject do |method|
            name = method.children.first
            METADATA_KEYS.include?(name)
          end

          expected_order = method_nodes.sort_by do |method|
            RuboCop::Cask::Constants::UNINSTALL_METHODS_ORDER.index(method.children.first) || -1
          end
          method_nodes.each_with_index do |method, index|
            next if method == expected_order[index]

            add_offense(method, message: format(MSG, method: method.children.first)) do |corrector|
              ordered_pairs = expected_order.map do |expected_method|
                hash_node.pairs.find { |pair| pair.key == expected_method }
              end

              indentation = " " * (start_column(method) - line_start_column(method))
              new_code = build_uninstall_body(ordered_pairs, comments, indentation)

              corrector.replace(hash_node.source_range, new_code)
            end
          end

          check_metadata(hash_node, comments)
        end

        private

        sig {
          params(
            hash_node: AST::HashNode,
            comments:  T::Array[Parser::Source::Comment],
          ).void
        }
        def check_metadata(hash_node, comments)
          on_upgrade_pair = hash_node.pairs.find { |p| p.key.value == :on_upgrade }
          return unless on_upgrade_pair

          on_upgrade_value = on_upgrade_pair.value
          requested = if on_upgrade_value.sym_type?
            [T.cast(on_upgrade_value, AST::SymbolNode).value]
          elsif on_upgrade_value.array_type?
            on_upgrade_value.children.select(&:sym_type?).map do |child|
              T.cast(child, AST::SymbolNode).value
            end
          else
            []
          end
          if requested.empty?
            add_offense(on_upgrade_value, message: "`on_upgrade` value must be :signal or an array [:signal]")
            return
          end

          available = []
          available << :signal if hash_node.pairs.any? { |p| p.key.value == :signal }

          valid_syms   = requested & available
          invalid_syms = requested - available

          if valid_syms.empty?
            remaining_pairs = hash_node.pairs.reject { |p| p == on_upgrade_pair }
            report_and_correct_useless_metadata(hash_node, on_upgrade_pair, remaining_pairs, comments)
          elsif invalid_syms.any?
            symbols_str = invalid_syms.map { |s| ":#{s}" }.join(", ")
            add_offense(on_upgrade_value, message: format(PARTIAL_METADATA_MSG, symbols: symbols_str))
          end
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
            first_pair = remaining_pairs.fetch(0)
            indentation = " " * (start_column(first_pair.key) - line_start_column(first_pair.key))

            new_code = build_uninstall_body(remaining_pairs, comments, indentation)
            corrector.replace(hash_node.source_range, new_code)
          end
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
      end
    end
  end
end
