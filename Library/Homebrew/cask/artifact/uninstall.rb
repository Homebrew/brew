# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `uninstall` stanza.
    class Uninstall < AbstractUninstall
      UPGRADE_REINSTALL_SKIP_DIRECTIVES = [:signal].freeze

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
        raw_on_upgrade = directives[:on_upgrade]
        on_upgrade_syms =
          case raw_on_upgrade
          when Symbol
            [raw_on_upgrade]
          when Array
            raw_on_upgrade.map(&:to_sym)
          else
            []
          end
        on_upgrade_set = on_upgrade_syms.to_set

        filtered_directives = ORDERED_DIRECTIVES.filter do |directive_sym|
          next false if directive_sym == :rmdir
          next false if directive_sym == :quit && !quit

          if (upgrade || reinstall) &&
             UPGRADE_REINSTALL_SKIP_DIRECTIVES.include?(directive_sym) &&
             on_upgrade_set.exclude?(directive_sym)
            next false
          end

          true
        end

        filtered_directives.each do |directive_sym|
          dispatch_uninstall_directive(directive_sym, command:, force:, successor:, upgrade:)
        end
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
        dispatch_uninstall_directive(:rmdir, command:, force:, successor:)
      end
    end
  end
end
