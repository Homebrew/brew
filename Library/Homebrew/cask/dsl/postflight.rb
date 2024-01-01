# typed: true
# frozen_string_literal: true

require "cask/staged"

module Cask
  class DSL
    # Class corresponding to the `postflight` stanza.
    #
    # @api private
    class Postflight < Base
      include Staged

      def suppress_move_to_applications(_options = {})
        odisabled "Cask::DSL#suppress_move_to_applications"
      end
    end
  end
end
