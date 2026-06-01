# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/install_steps_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks declarative install step usage.
      class InstallSteps < FormulaCop
        extend AutoCorrector
        include InstallStepsHelper

        CONFLICT_MSG = "`post_install` and `post_install_steps` cannot both be used."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          post_install_steps_block = find_block(body_node, :post_install_steps)
          post_install_method = find_method_def(body_node, :post_install)
          if post_install_steps_block && post_install_method
            offending_node(post_install_steps_block)
            problem CONFLICT_MSG
          end

          audit_step_block(post_install_steps_block)
          audit_post_install_method(post_install_method) if post_install_steps_block.nil?
        end

        private

        sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).void }
        def audit_step_block(block_node)
          return unless (offense_node = install_step_block_offense_node(block_node))

          offending_node(offense_node)
          problem STEP_BLOCK_MSG
        end

        sig { params(post_install_method: T.nilable(RuboCop::AST::Node)).void }
        def audit_post_install_method(post_install_method)
          return if post_install_method.nil?
          return unless post_install_method.def_type?

          post_install_def = T.cast(post_install_method, RuboCop::AST::DefNode)
          step_lines = simple_install_step_lines(post_install_def.body,
                                                 default_base:        :var,
                                                 default_source_base: :prefix,
                                                 default_target_base: :prefix)
          return if step_lines.blank?

          add_offense(post_install_method,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block: "post_install_steps")) do |corrector|
            corrector.replace(
              post_install_method.source_range,
              install_steps_block_source(:post_install_steps, step_lines, post_install_method.source_range.column),
            )
          end
        end
      end
    end
  end
end
