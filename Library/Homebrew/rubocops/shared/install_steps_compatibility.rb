# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module InstallStepsHelper
      # Corrections for legacy install-step methods and keywords.
      module InstallStepsCompatibility
        extend T::Helpers

        requires_ancestor { InstallStepsHelper }

        private

        sig { params(send_node: RuboCop::AST::SendNode).void }
        def add_compatibility_step_keyword_offenses(send_node)
          replacements = COMPATIBILITY_STEP_KEYWORD_REPLACEMENTS[send_node.method_name]
          return if replacements.nil?

          options = send_node.last_argument
          return unless options&.hash_type?

          options = T.cast(options, RuboCop::AST::HashNode)
          options.pairs.each do |pair|
            next unless pair.key.sym_type?
            next unless (replacement = replacements[pair.key.value])

            message = Kernel.format(LEGACY_STEP_KEYWORD_MSG, keyword: pair.key.value, replacement:)
            add_offense(pair.key.source_range, message:) do |corrector|
              correct_compatibility_step_keyword(corrector, send_node, options, pair, replacement)
            end
          end
        end

        sig {
          params(
            corrector:   RuboCop::Cop::Corrector,
            send_node:   RuboCop::AST::SendNode,
            options:     RuboCop::AST::HashNode,
            legacy_pair: RuboCop::AST::PairNode,
            replacement: Symbol,
          ).void
        }
        def correct_compatibility_step_keyword(corrector, send_node, options, legacy_pair, replacement)
          if replacement == :fingerprint_of
            corrector.replace(legacy_pair.key.source_range, replacement.to_s)
            return
          end
          return if !legacy_pair.value.true_type? && !legacy_pair.value.false_type?

          canonical_pair = options.pairs.find do |pair|
            pair != legacy_pair && pair.key.sym_type? && pair.key.value == replacement
          end
          if legacy_pair.value.true_type? && canonical_pair.nil?
            corrector.replace(legacy_pair.key.source_range, replacement.to_s)
            return
          end

          if legacy_pair.value.true_type? && canonical_pair && !canonical_pair.value.true_type?
            corrector.replace(canonical_pair.value.source_range, "true")
          end
          pairs = options.pairs
          index = pairs.index(legacy_pair)
          return if index.nil?

          range = if (next_pair = pairs[index + 1])
            legacy_pair.source_range.begin.join(next_pair.source_range.begin)
          elsif (previous_pair = pairs[index - 1]) && index.positive?
            previous_pair.source_range.end.join(legacy_pair.source_range.end)
          else
            send_node.arguments.fetch(-2).source_range.end.join(legacy_pair.source_range.end)
          end
          corrector.remove(range)
        end

        sig {
          params(
            corrector: RuboCop::Cop::Corrector,
            send_node: RuboCop::AST::SendNode,
          ).void
        }
        def add_compatibility_step_method_corrections(corrector, send_node)
          case send_node.method_name
          when :ln_sf
            add_step_keyword(corrector, send_node, "overwrite: true")
          when :write
            options = send_node.last_argument
            overwrite = options&.hash_type? && T.cast(options, RuboCop::AST::HashNode).pairs.any? do |pair|
              pair.key.sym_type? && pair.key.value == :overwrite
            end
            keyword = "append_newline: true"
            keyword = "overwrite: false, #{keyword}" unless overwrite
            add_step_keyword(corrector, send_node, keyword)
          end
        end

        sig {
          params(
            corrector: RuboCop::Cop::Corrector,
            send_node: RuboCop::AST::SendNode,
            keyword:   String,
          ).void
        }
        def add_step_keyword(corrector, send_node, keyword)
          options = send_node.last_argument
          if options&.hash_type?
            options = T.cast(options, RuboCop::AST::HashNode)
            if (pair = options.pairs.last)
              corrector.insert_after(pair.source_range, ", #{keyword}")
            else
              corrector.replace(options, keyword)
            end
          elsif (argument = send_node.last_argument)
            range = if argument.loc.respond_to?(:heredoc_end) && argument.loc.heredoc_end
              argument.loc.expression
            else
              argument.source_range
            end
            corrector.insert_after(range, ", #{keyword}")
          end
        end
      end
    end
  end
end
