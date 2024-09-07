# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # Common functionality for checking homepage stanzas.
      module OnHomepageStanza
        extend Forwardable
        include CaskHelp

        def on_cask(cask_block)
          @cask_block = cask_block

          toplevel_stanzas.select(&:homepage?).each do |stanza|
            on_homepage_stanza(stanza)
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
