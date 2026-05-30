# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "trust"

module Homebrew
  module Cmd
    class Untrust < AbstractCommand
      cmd_args do
        description <<~EOS
          Stop trusting non-official tap formulae, casks or commands.
        EOS
        hide_from_man_page!

        switch "--tap",
               description: "Untrust the named tap."
        switch "--formula", "--formulae",
               description: "Untrust the named formula."
        switch "--cask", "--casks",
               description: "Untrust the named cask."
        switch "--command", "--commands",
               description: "Untrust the named external command."

        conflicts "--tap", "--formula", "--cask", "--command"

        named_args :target, min: 1
      end

      sig { override.void }
      def run
        args.named.each do |name|
          type, trust_name = Homebrew::Trust.target(name, type: selected_type, include_existing: true)
          if type == :tap && Tap.fetch(trust_name).official?
            puts "Official tap #{trust_name} is always trusted."
            next
          end

          action = Homebrew::Trust.untrust!(type, trust_name) ? "Untrusted" : "Not trusted"

          puts "#{action} #{type}: #{trust_name}"
        end
      end

      private

      sig { returns(T.nilable(Symbol)) }
      def selected_type
        return :tap if args.tap?
        return :formula if args.formula?
        return :cask if args.cask?

        :command if args.command? || args.commands?
      end
    end
  end
end
