# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `option`s in formulae.
      class Options < FormulaCop
        DEP_OPTION = "Formulae in homebrew/core should not use `deprecated_option`."
        OPTION = "Formulae in homebrew/core should not use `option`."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          option_call_nodes = find_every_method_call_by_name(body_node, :option)
          option_call_nodes.each do |option_call|
            option = parameters(option_call).first
            offending_node(option_call)
            option = string_content(option)

            unless /with(out)?-/.match?(option)
              problem "Options should begin with `with` or `without`. " \
                      "Migrate '--#{option}' with `deprecated_option`."
            end

            next unless option =~ /^with(out)?-(?:checks?|tests)$/
            next if depends_on?("check", :optional, :recommended)

            problem "Use '--with#{Regexp.last_match(1)}-test' instead of '--#{option}'. " \
                    "Migrate '--#{option}' with `deprecated_option`."
          end

          return if formula_tap != "homebrew-core"

          problem DEP_OPTION if method_called_ever?(body_node, :deprecated_option)
          problem OPTION if method_called_ever?(body_node, :option)
        end
      end
    end
  end
end
