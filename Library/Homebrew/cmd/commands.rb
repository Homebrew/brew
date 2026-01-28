# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class CommandsCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Show lists of built-in and external commands.
        EOS
        switch "-q", "--quiet",
               description: "List only the names of commands without category headers."
        switch "--include-aliases",
               depends_on:  "--quiet",
               description: "Include aliases of internal commands."

        named_args :none
      end

      sig { override.void }
      def run
        if args.quiet?
          puts Formatter.columns(Commands.commands(aliases: args.include_aliases?))
          return
        end

        prepend_separator = T.let(false, T::Boolean)

        {
          "Built-in commands"           => Commands.internal_commands,
          "Built-in developer commands" => Commands.internal_developer_commands,
          "External commands"           => Commands.external_commands,
        }.each do |title, commands|
          next if commands.blank?

          puts if prepend_separator
          ohai title, Formatter.columns(commands)

          prepend_separator ||= true
        end
      end
    end
  end
end
