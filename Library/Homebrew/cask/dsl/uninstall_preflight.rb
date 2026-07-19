# typed: strict
# frozen_string_literal: true

require "cask/staged"

module Cask
  class DSL
    # Class corresponding to the `uninstall_preflight` stanza.
    # deadcode:keep instantiated dynamically via `const_get` in AbstractFlightBlock
    class UninstallPreflight < Base
      include Staged
    end
  end
end
