# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `uninstall` stanza.
    class Uninstall < AbstractUninstall
      sig {
        params(
          command:   T.class_of(SystemCommand),
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          quit:      T::Boolean,
        ).void
      }
      def uninstall_phase(command:, skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, quit: true)
        AbstractUninstall.dispatch_directives([self], command:, force:, successor:, upgrade:, reinstall:, quit:)
      end

      sig {
        params(
          command:   T.class_of(SystemCommand),
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
        ).void
      }
      def post_uninstall_phase(command:, skip: false, force: false, verbose: false, successor: nil)
        AbstractUninstall.dispatch_directives([self], command:, deferred: true, force:, successor:)
      end
    end
  end
end
