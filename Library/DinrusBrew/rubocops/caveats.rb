# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop ensures that caveats don't recommend unsupported or unsafe operations.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # def caveats
      #   <<~EOS
      #     Use `setuid` to allow running the executable by non-root users.
      #   EOS
      # end
      #
      # # good
      # def caveats
      #   <<~EOS
      #     Use `sudo` to run the executable.
      #   EOS
      # end
      # ```
      class Caveats < FormulaCop
        sig { override.params(_formula_nodes: FormulaNodes).void }
        def audit_formula(_formula_nodes)
          caveats_strings.each do |n|
            if regex_match_group(n, /\bsetuid\b/i)
              problem "Don't recommend `setuid` in the caveats, suggest `sudo` instead."
            end

            problem "Don't use ANSI escape codes in the caveats." if regex_match_group(n, /\e/)
          end
        end
      end
    end
  end
end
