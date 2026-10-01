# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/cask"

module Homebrew
  module Cmd
    class Pin < AbstractCommand
      cmd_args do
        description <<~EOS
          Pin the specified package, preventing it from being upgraded when
          issuing the `brew upgrade` <formula> or <cask> command. See also `unpin`.

          *Note:* Other packages which depend on newer versions of a pinned formula
          might not install or run correctly.
          Pinned casks with `auto_updates true` may update themselves outside Homebrew.
        EOS

        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--formula", "--cask"

        named_args [:installed_formula, :installed_cask], min: 1
      end

      sig { override.void }
      def run
        formulae, casks = args.named.to_resolved_formulae_to_casks

        (formulae + casks).each do |package|
          if package.pinned?
            opoo "#{package.full_name} already pinned"
          elsif !package.pinnable?
            ofail "#{package.full_name} not installed"
          else
            package.pin
            if package.is_a?(Cask::Cask) && package.auto_updates
              opoo "#{package.full_name} has `auto_updates true` and may update itself outside Homebrew despite " \
                   "being pinned."
            end
          end
        end
      end
    end
  end
end
