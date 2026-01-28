# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `uninstall` stanza.
    class Uninstall < AbstractUninstall
      UPGRADE_REINSTALL_SKIP_DIRECTIVES = [:quit, :signal].freeze

      def uninstall_phase(**options)
        upgrade   = options.fetch(:upgrade, false)
        reinstall = options.fetch(:reinstall, false)

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

          if (upgrade || reinstall) &&
             UPGRADE_REINSTALL_SKIP_DIRECTIVES.include?(directive_sym) &&
             on_upgrade_set.exclude?(directive_sym)
            next false
          end

          true
        end

        filtered_directives.each do |directive_sym|
          dispatch_uninstall_directive(directive_sym, **options)
        end
      end

      def post_uninstall_phase(**options)
        dispatch_uninstall_directive(:rmdir, **options)
      end
    end
  end
end
