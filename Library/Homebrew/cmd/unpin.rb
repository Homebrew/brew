# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/cask"

module Homebrew
  module Cmd
    class Unpin < AbstractCommand
      cmd_args do
        description <<~EOS
          Unpin the specified package, allowing it to be upgraded by `brew upgrade` <formula> or <cask>.
          See also `pin`.
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

        formulae.each do |formula|
          if formula.pinned?
            formula.unpin
          elsif !formula.pinnable?
            onoe "#{formula.full_name} not installed"
          else
            opoo "#{formula.full_name} not pinned"
          end
        end

        casks.each do |cask|
          if cask.pinned? || cask.pin_path.symlink?
            cask.unpin
          elsif !cask.pinnable?
            onoe "#{cask.full_name} not installed"
          else
            opoo "#{cask.full_name} not pinned"
          end
        end
      end
    end
  end
end
