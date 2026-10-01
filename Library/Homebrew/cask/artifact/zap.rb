# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `zap` stanza.
    class Zap < AbstractUninstall
      sig {
        params(
          command: T.class_of(SystemCommand),
          force:   T::Boolean,
          verbose: T::Boolean,
        ).void
      }
      def zap_phase(command:, force: false, verbose: false)
        dispatch_uninstall_directives(command:, force:)
      end
    end
  end
end
