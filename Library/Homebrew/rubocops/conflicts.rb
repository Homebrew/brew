# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits versioned formulae for `conflicts_with`.
      class Conflicts < FormulaCop
        extend AutoCorrector

        MSG = "Versioned formulae should not use `conflicts_with`. " \
              "Use `keg_only :versioned_formula` instead."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          find_method_calls_by_name(body_node, :conflicts_with).each do |conflicts_with_call|
            next unless parameters(conflicts_with_call).last.respond_to? :values

            reason = parameters(conflicts_with_call).last.values.first
            offending_node(reason)
            name = Regexp.new(T.must(@formula_name), Regexp::IGNORECASE)
            reason_text = string_content(reason).sub(name, "")
            first_word = reason_text.split.first

            if reason_text.match?(/\A[A-Z]/)
              problem "'#{first_word}' from the `conflicts_with` reason " \
                      "should be '#{first_word.downcase}'." do |corrector|
                reason_text[0] = reason_text[0].downcase
                corrector.replace(reason.source_range, "\"#{reason_text}\"")
              end
            end
            next unless reason_text.end_with?(".")

            problem "`conflicts_with` reason should not end with a period." do |corrector|
              corrector.replace(reason.source_range, "\"#{reason_text.chop}\"")
            end
          end

          return unless versioned_formula?

          if !tap_style_exception?(:versioned_formulae_conflicts_allowlist) && method_called_ever?(body_node,
                                                                                                   :conflicts_with)
            problem MSG do |corrector|
              corrector.replace(T.must(@offensive_node).source_range, "keg_only :versioned_formula")
            end
          end
        end
      end
    end
  end
end
