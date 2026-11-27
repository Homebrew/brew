# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAuditStrict
      # This cop makes sure that no build-time checks are performed.
      class MakeCheck < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          # Avoid build-time checks in homebrew/core
          return if formula_tap != "homebrew-core"
          return if formula_name.start_with?("lib")
          return if tap_style_exception? :make_check_allowlist
          return if (body_node = formula_nodes.body_node).nil?

          make_check(body_node) do |method|
            offending_node(method)
            problem "Formulae in homebrew/core (except e.g. cryptography, libraries) " \
                    "should not run build-time checks"
          end
        end

        def_node_search :make_check, <<~PATTERN
          {(send nil? :system (str /^g?make$/) <(str /^(checks?|tests?)$/) ...>)
           (send nil? :system (str "ctest") ...)
           (send nil? :system (str "meson") (str "test") ...)}
        PATTERN
      end
    end
  end
end
