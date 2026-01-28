# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that a `keg_only` reason has the correct format.
      class KegOnly < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          keg_only_node = find_node_method_by_name(formula_nodes.body_node, :keg_only)
          return unless keg_only_node

          allowlist = %w[
            Apple
            macOS
            OS
            Homebrew
            Xcode
            GPG
            GNOME
            BSD
            Firefox
          ].freeze

          reason = parameters(keg_only_node).first
          offending_node(reason)
          name = Regexp.new(T.must(@formula_name), Regexp::IGNORECASE)
          reason = string_content(reason).sub(name, "")
          first_word = reason.split.first

          if /\A[A-Z]/.match?(reason) && !reason.start_with?(*allowlist)
            problem "'#{first_word}' from the `keg_only` reason should be '#{first_word.downcase}'." do |corrector|
              reason[0] = reason[0].downcase
              corrector.replace(T.must(@offensive_node).source_range, "\"#{reason}\"")
            end
          end

          return unless reason.end_with?(".")

          problem "`keg_only` reason should not end with a period." do |corrector|
            corrector.replace(T.must(@offensive_node).source_range, "\"#{reason.chop}\"")
          end
        end

        sig { params(node: RuboCop::AST::Node).void }
        def autocorrect(node)
          lambda do |corrector|
            reason = string_content(node)
            reason[0] = reason[0].downcase
            reason = reason.delete_suffix(".")
            corrector.replace(node.source_range, "\"#{reason}\"")
          end
        end
      end
    end
  end
end
