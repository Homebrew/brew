# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop ensures that caveats don't have problematic text or logic.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # def caveats
      #   if File.exist?("/etc/issue")
      #     "This caveat only when file exists that won't work with JSON API."
      #   end
      # end
      #
      # # good
      # def caveats
      #   "This caveat always works regardless of the JSON API."
      # end
      #
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
              problem "Instead of recommending `setuid` in the caveats, suggest `sudo`."
            end

            problem "Don't use ANSI escape codes in the caveats." if regex_match_group(n, /\e/)
          end

          return if formula_tap != "homebrew-core"

          # Forbid dynamic logic in caveats (only if/else/unless)
          caveats_method = find_method_def(@body, :caveats)
          return unless caveats_method

          dynamic_nodes = caveats_method.each_descendant.select do |descendant|
            descendant.type == :if
          end
          dynamic_nodes.each do |node|
            @offensive_node = node
            problem "Don't use dynamic logic (if/else/unless) in caveats."
          end
        end
      end
    end
  end
end
