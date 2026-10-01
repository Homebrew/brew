# typed: strict
# frozen_string_literal: true

require "utils/editor"

require "abstract_subcommand"

module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class EditSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew bundle edit`:
            Edit the `Brewfile` in your editor.
          EOS
          named_args :none
          switch "--install",
                 description: "Run `install` before editing the `Brewfile`."
        end

        sig { override.void }
        def run
          require "bundle/brewfile"

          Utils::Editor.open(Homebrew::Bundle::Brewfile.path(global: context.global, file: context.file))
        end
      end
    end
  end
end
