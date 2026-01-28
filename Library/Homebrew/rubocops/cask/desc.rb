# typed: strict
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

        sig { params(stanza: RuboCop::Cask::AST::Stanza).void }
        def on_desc_stanza(stanza)
          @name = T.let(cask_block&.header&.cask_token, T.nilable(String))
          desc_call = stanza.stanza_node
          audit_desc(:cask, @name, desc_call)
        end
      end
    end
  end
end
