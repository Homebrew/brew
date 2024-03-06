# typed: true
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `zap` stanza.
    class Zap < AbstractUninstall
      def zap_phase(**options)
        dispatch_uninstall_directives(**options)
      end
    end
  end
end
