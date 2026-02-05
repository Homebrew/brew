# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "utils/shell"

module Homebrew
  module Cmd
    class CommandNotFoundInit < AbstractCommand
      cmd_args do
        description <<~EOS
          Print instructions for setting up the command-not-found hook for your shell.
          If the output is not to a tty, print the appropriate handler script for your shell.

          For more information, see:
            https://docs.brew.sh/Command-Not-Found
        EOS
        named_args :none
      end

      sig { override.void }
      def run
        if $stdout.tty?
          help
        else
          init
        end
      end

      sig { returns(T.nilable(Symbol)) }
      def shell
        Utils::Shell.parent || Utils::Shell.preferred
      end

      sig { void }
      def init
        case shell
        when :bash, :zsh
          puts File.read(File.expand_path("#{File.dirname(__FILE__)}/../command-not-found/handler.sh"))
        when :fish
          puts File.read(File.expand_path("#{File.dirname(__FILE__)}/../command-not-found/handler.fish"))
        else
          raise "Unsupported shell type #{shell}"
        end
      end

      sig { void }
      def help
        case shell
        when :bash, :zsh
          puts <<~EOS
            # To enable command-not-found
            # Add the following lines to ~/.#{shell}rc

            HOMEBREW_COMMAND_NOT_FOUND_HANDLER="$(brew --repository)/Library/Homebrew/command-not-found/handler.sh"
            if [ -f "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER" ]; then
              source "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER";
            fi
          EOS
        when :fish
          puts <<~EOS
            # To enable command-not-found
            # Add the following line to ~/.config/fish/config.fish

            set HOMEBREW_COMMAND_NOT_FOUND_HANDLER (brew --repository)/Library/Homebrew/command-not-found/handler.fish
            if test -f $HOMEBREW_COMMAND_NOT_FOUND_HANDLER
              source $HOMEBREW_COMMAND_NOT_FOUND_HANDLER
            end
          EOS
        else
          raise "Unsupported shell type #{shell}"
        end
      end
    end
  end
end
