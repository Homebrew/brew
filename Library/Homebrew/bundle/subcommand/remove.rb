# typed: strict
# frozen_string_literal: true

require "utils/text"

require "abstract_subcommand"
require "bundle/extensions/extension"

require "bundle/remover"
module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class RemoveSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          extensions = Homebrew::Bundle.extensions
          usage_banner <<~EOS
            `brew bundle remove` <name> [...]:
            Remove entries that match `name` from your `Brewfile`. Use #{Utils::Text.to_sentence(["`--formula`", "`--cask`", "`--tap`", *extensions.select(&:remove_supported?).map { |extension| "`--#{extension.flag}`" }])} to remove only entries of the corresponding type. Passing `--formula` also removes matches against formula aliases and old formula names.
          EOS
          named_args min: 1
          switch "--install",
                 description: "Run `install` before removing entries."
          switch "--formula", "--formulae", "--brews",
                 description: "Remove Homebrew formula entries, including matches against formula aliases " \
                              "and old names."
          switch "--cask", "--casks",
                 description: "Remove Homebrew cask entries."
          switch "--tap", "--taps",
                 description: "Remove Homebrew tap entries."
          extensions.select(&:remove_supported?).each do |extension|
            switch "--#{extension.flag}",
                   description: extension.switch_description("Remove entries for #{extension.banner_name}.")
          end
        end

        sig { override.void }
        def run
          selected_types = context.selected_types(args)
          raise UsageError, "`remove` supports only one type of entry at a time." if selected_types.count != 1

          Homebrew::Bundle::Remover.remove(
            *args.named,
            type:   selected_types.first,
            global: context.global,
            file:   context.file,
          )
        end
      end
    end
  end
end
