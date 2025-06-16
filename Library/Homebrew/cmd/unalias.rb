# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "aliases/aliases"

module Homebrew
  module Cmd
    class Unalias < AbstractCommand
      cmd_args do
        description <<~EOS
          Remove aliases.
        EOS
        named_args :alias, min: 1
      end

      sig { override.void }
      def run
        Aliases.init
        args.named.each { |a| Aliases.remove a }
      end
    end
  end
end
