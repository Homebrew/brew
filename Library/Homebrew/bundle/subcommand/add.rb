# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "bundle/extensions/extension"

require "bundle/adder"
module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class AddSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          extensions = Homebrew::Bundle.extensions
          usage_banner <<~EOS
            `brew bundle add` <name> [...]:
            Add entries to your `Brewfile`. Adds formulae by default. Use #{["`--cask`", "`--tap`", *extensions.select(&:add_supported?).map { |extension| "`--#{extension.flag}`" }].to_sentence} to add the corresponding entry instead.
          EOS
          named_args min: 1
          switch "--install",
                 description: "Run `install` before adding entries."
          switch "--formula", "--formulae", "--brews",
                 description: "Add Homebrew formula entries."
          switch "--cask", "--casks",
                 description: "Add Homebrew cask entries."
          switch "--tap", "--taps",
                 description: "Add Homebrew tap entries."
          extensions.select(&:add_supported?).each do |extension|
            switch "--#{extension.flag}",
                   description: extension.switch_description("Add entries for #{extension.banner_name}.")
          end
          switch "--no-describe",
                 description: "Do not add description comments above each line. Description comments are " \
                              "the default.",
                 env:         :bundle_no_describe
          switch "--describe",
                 description: "Add a description comment above each line, unless the " \
                              "dependency does not have a description. This is the default unless " \
                              "`$HOMEBREW_BUNDLE_NO_DESCRIBE` is set.",
                 env:         :bundle_describe,
                 replacement: "the default behaviour",
                 odeprecated: true
          conflicts "--describe", "--no-describe"
        end

        sig { override.void }
        def run
          selected_types = context.selected_types(args)
          raise UsageError, "`add` supports only one type of entry at a time." if selected_types.count != 1

          type = case (t = selected_types.first)
          when :none then :brew
          when :mas then raise UsageError, "`add` does not support `--mas`."
          else t
          end

          extension = Homebrew::Bundle.extension(type)
          if extension && !extension.add_supported?
            raise UsageError,
                  "`add` does not support `--#{extension.flag}`."
          end

          Homebrew::Bundle::Adder.add(
            *args.named,
            type:,
            global:   context.global,
            file:     context.file,
            describe: args.describe? && !args.no_describe?,
          )
        end
      end
    end
  end
end
