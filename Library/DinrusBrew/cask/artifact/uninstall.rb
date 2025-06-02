# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/abstract_uninstall"

module Cask
  module Artifact
    # Artifact corresponding to the `uninstall` stanza.
    class Uninstall < AbstractUninstall
      UPGRADE_REINSTALL_SKIP_DIRECTIVES = [:quit, :signal].freeze

      def uninstall_phase(upgrade: false, reinstall: false, **options)
        filtered_directives = ORDERED_DIRECTIVES.filter do |directive_sym|
          next false if directive_sym == :rmdir

          next false if (upgrade || reinstall) && UPGRADE_REINSTALL_SKIP_DIRECTIVES.include?(directive_sym)

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
