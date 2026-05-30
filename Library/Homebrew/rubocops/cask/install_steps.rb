# typed: strict
# frozen_string_literal: true

require "rubocops/shared/install_steps_helper"

module RuboCop
  module Cop
    module Cask
      # This cop checks declarative install step usage.
      class InstallSteps < Base
        extend AutoCorrector
        include CaskHelp
        include ::RuboCop::Cop::InstallStepsHelper

        INSTALL_STEP_PAIRS = T.let(
          {
            preflight:            :preflight_steps,
            postflight:           :postflight_steps,
            uninstall_preflight:  :uninstall_preflight_steps,
            uninstall_postflight: :uninstall_postflight_steps,
          }.freeze,
          T::Hash[Symbol, Symbol],
        )

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          stanzas = cask_block.stanzas
          INSTALL_STEP_PAIRS.each do |flight_block, steps_block|
            next unless (flight_stanza = stanzas.find { |stanza| stanza.stanza_name == flight_block })

            steps_stanza = stanzas.find { |stanza| stanza.stanza_name == steps_block }

            if steps_stanza
              add_offense(steps_stanza.source_range,
                          message: "`#{flight_stanza.stanza_name}` and `#{steps_block}` cannot both be used.")
            else
              audit_flight_block(flight_stanza, steps_block)
            end
          end

          stanzas.each do |stanza|
            next unless INSTALL_STEP_PAIRS.value?(stanza.stanza_name)
            next unless stanza.method_node.block_type?
            next unless (offense_node = install_step_block_offense_node(T.cast(stanza.method_node,
                                                                               RuboCop::AST::BlockNode)))

            add_offense(offense_node, message: STEP_BLOCK_MSG)
          end
        end

        private

        sig { params(flight_stanza: RuboCop::Cask::AST::Stanza, steps_block: Symbol).void }
        def audit_flight_block(flight_stanza, steps_block)
          return unless flight_stanza.method_node.block_type?

          block_node = T.cast(flight_stanza.method_node, RuboCop::AST::BlockNode)
          step_lines = simple_install_step_lines(block_node.body,
                                                 default_base:        :staged_path,
                                                 default_source_base: :staged_path,
                                                 default_target_base: :staged_path)
          return if step_lines.blank?

          add_offense(block_node.source_range,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block:)) do |corrector|
            corrector.replace(
              block_node.source_range,
              install_steps_block_source(steps_block, step_lines, block_node.source_range.column),
            )
          end
        end
      end
    end
  end
end
