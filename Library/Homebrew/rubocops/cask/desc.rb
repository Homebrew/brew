# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "rubocops/cask/mixin/on_desc_stanza"
require "rubocops/shared/desc_helper"

module RuboCop
  module Cop
    module Cask
      # This cop audits `desc` in casks.
      # See the {DescHelper} module for details of the checks.
      class Desc < Base
        include OnDescStanza
        include DescHelper
        extend AutoCorrector

        def on_desc_stanza(stanza)
          @name = cask_block.header.cask_token
          desc_call = stanza.stanza_node
          audit_desc(:cask, @name, desc_call)
        end
      end
    end
  end
end
