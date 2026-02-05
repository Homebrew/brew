# typed: strict
# frozen_string_literal: true

require "forwardable"
require "rubocops/shared/no_autobump_helper"

module RuboCop
  module Cop
    module Cask
      # This cop audits `no_autobump!` reason.
      # See the {NoAutobumpHelper} module for details of the checks.
      class NoAutobump < Base
        extend Forwardable
        extend AutoCorrector
        include CaskHelp
        include NoAutobumpHelper

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          @cask_block = T.let(cask_block, T.nilable(RuboCop::Cask::AST::CaskBlock))

          toplevel_stanzas.select(&:no_autobump?).each do |stanza|
            no_autobump_node = stanza.stanza_node

            reason_found = T.let(false, T::Boolean)
            reason(no_autobump_node) do |reason_node|
              reason_found = true
              audit_no_autobump(:cask, reason_node)
            end

            next if reason_found

            problem 'Add a reason for exclusion from autobump: `no_autobump! because: "..."`'
          end
        end

        private

        sig { returns(T.nilable(RuboCop::Cask::AST::CaskBlock)) }
        attr_reader :cask_block

        def_delegators :cask_block, :toplevel_stanzas

        def_node_search :reason, <<~EOS
          (pair (sym :because) ${str sym})
        EOS
      end
    end
  end
end
