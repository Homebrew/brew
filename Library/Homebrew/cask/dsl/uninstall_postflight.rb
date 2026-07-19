# typed: strict
# frozen_string_literal: true

module Cask
  class DSL
    # Class corresponding to the `uninstall_postflight` stanza.
    # deadcode:keep instantiated dynamically via `const_get` in AbstractFlightBlock
    class UninstallPostflight < Base
    end
  end
end
