# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "aliases/aliases"

module Homebrew
  module Cmd
    class Alias < AbstractCommand
      cmd_args do
        usage_banner "`alias` [`--edit`] [<alias>|<alias>=<command>]"
        description <<~EOS
          Show an alias's command. If no alias is given, print the whole list.
        EOS
        switch "--edit",
               description: "Edit aliases in a text editor. Either one or all aliases may be opened at once. " \
                            "If the given alias doesn't exist it'll be pre-populated with a template."

        named_args max: 1
      end

      sig { override.void }
      def run
        name = args.named.first
        name, command = name.split("=", 2) if name.present?

        Aliases.init

        if name.nil?
          if args.edit?
            Aliases.edit_all
          else
            Aliases.show
          end
        elsif command.nil?
          if args.edit?
            Aliases.edit name
          else
            Aliases.show name
          end
        else
          Aliases.add name, command
          Aliases.edit name if args.edit?
        end
      end
    end
  end
end
