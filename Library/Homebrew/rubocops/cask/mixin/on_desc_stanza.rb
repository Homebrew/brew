# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # Common functionality for checking desc stanzas.
      module OnDescStanza
        extend Forwardable
        include CaskHelp

        def on_cask(cask_block)
          @cask_block = cask_block

          toplevel_stanzas.select(&:desc?).each do |stanza|
            on_desc_stanza(stanza)
          end
        end

        private

        attr_reader :cask_block

        def_delegators :cask_block,
                       :toplevel_stanzas
      end
    end
  end
end
