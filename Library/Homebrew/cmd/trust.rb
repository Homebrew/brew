# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "trust"

module Homebrew
  module Cmd
    class Trust < AbstractCommand
      cmd_args do
        description <<~EOS
          Trust non-official tap formulae, casks or commands so Homebrew may load them when
          `$HOMEBREW_REQUIRE_TAP_TRUST` is set.
        EOS
        hide_from_man_page!

        switch "--tap",
               description: "Trust the named tap."
        switch "--formula", "--formulae",
               description: "Trust the named formula."
        switch "--cask", "--casks",
               description: "Trust the named cask."
        switch "--command", "--commands",
               description: "Trust the named external command."

        conflicts "--tap", "--formula", "--cask", "--command"

        named_args :target, min: 1
      end

      sig { override.void }
      def run
        args.named.each do |name|
          type, trust_name = Homebrew::Trust.target(name, type: selected_type)
          if type == :tap && Tap.fetch(trust_name).official?
            puts "Official tap #{trust_name} is always trusted."
            next
          end

          action = Homebrew::Trust.trust!(type, trust_name) ? "Trusted" : "Already trusted"

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
