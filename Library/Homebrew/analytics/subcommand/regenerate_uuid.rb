# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "utils/analytics"

module Homebrew
  module Cmd
    class Analytics < Homebrew::AbstractCommand
      class RegenerateUuidSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew analytics regenerate-uuid`:
            Delete Homebrew's legacy analytics UUID.
          EOS
          named_args :none
          hide_from_man_page!
        end

        sig { override.void }
        def run
          odisabled "brew analytics regenerate-uuid"
        end
      end
    end
  end
end
