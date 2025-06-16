# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "commands"

module Homebrew
  module Cmd
    class Command < AbstractCommand
      cmd_args do
        description <<~EOS
          Display the path to the file being used when invoking `brew` <cmd>.
        EOS

        named_args :command, min: 1
      end

      sig { override.void }
      def run
        args.named.each do |cmd|
          path = Commands.path(cmd)
          odie "Unknown command: brew #{cmd}" unless path
          puts path
        end
      end
    end
  end
end
