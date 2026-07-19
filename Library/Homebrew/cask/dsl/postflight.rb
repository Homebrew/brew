# typed: strict
# frozen_string_literal: true

require "cask/staged"

module Cask
  class DSL
    # Class corresponding to the `postflight` stanza.
    # deadcode:keep instantiated dynamically via `const_get` in AbstractFlightBlock
    class Postflight < Base
      include Staged
    end
  end
end
