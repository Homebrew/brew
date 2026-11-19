# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `deprecate!` and `disable!` dates.
      class DeprecateDisableDate < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node

          [:deprecate!, :disable!].each do |method|
            node = find_node_method_by_name(body_node, method)

            next if node.nil?

            date(node) do |date_node|
              Date.iso8601(string_content(date_node))
            rescue ArgumentError
              date_string = string_content(date_node)
              fixed_date_string = begin
                Date.parse(date_string).iso8601 if Date._parse(date_string).values_at(:year, :mon, :mday).all?
              rescue ArgumentError
                nil
              end
              @offensive_node = date_node
              if fixed_date_string
                problem "Use `#{fixed_date_string}` to comply with ISO 8601" do |corrector|
                  corrector.replace(date_node.source_range, "\"#{fixed_date_string}\"")
                end
              else
                problem "Use an ISO 8601 date (`YYYY-MM-DD`)"
              end
            end
          end
        end

        def_node_search :date, <<~EOS
          (pair (sym :date) $str)
        EOS
      end

      # This cop audits `deprecate!` and `disable!` reasons.
      class DeprecateDisableReason < FormulaCop
        extend AutoCorrector

        PUNCTUATION_MARKS = %w[. ! ?].freeze

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node

          [:deprecate!, :disable!].each do |method|
            node = find_node_method_by_name(body_node, method)

            next if node.nil?

            reason_found = T.let(false, T::Boolean)
            reason(node) do |reason_node|
              reason_found = true
              next if reason_node.sym_type?

              @offensive_node = reason_node
              reason_string = string_content(reason_node)

              if reason_string.start_with?("it ")
                problem "Do not start the reason with `it`" do |corrector|
                  corrector.replace(@offensive_node.source_range, "\"#{reason_string[3..]}\"")
                end
              end

              if PUNCTUATION_MARKS.include?(reason_string[-1])
                problem "Do not end the reason with a punctuation mark" do |corrector|
                  corrector.replace(@offensive_node.source_range, "\"#{reason_string.chop}\"")
                end
              end
            end

            next if reason_found

            case method
            when :deprecate!
              problem 'Add a reason for deprecation: `deprecate! because: "..."`'
            when :disable!
              problem 'Add a reason for disabling: `disable! because: "..."`'
            end
          end
        end

        def_node_search :reason, <<~EOS
          (pair (sym :because) ${str sym})
        EOS
      end
    end
  end
end
