# typed: strict
# frozen_string_literal: true

require "cask/staged"

module Cask
  class DSL
    # Class corresponding to the `preflight` stanza.
    class Preflight < Base
      include Staged
    end
  end
end
