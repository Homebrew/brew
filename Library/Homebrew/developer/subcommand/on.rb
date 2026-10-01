# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "env_config"
require "settings"
require "utils/tty"

module Homebrew
  module Cmd
    class Developer < Homebrew::AbstractCommand
      class OnSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew developer on`:
            Turn Homebrew's developer mode on.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Homebrew::Settings.write "devcmdrun", true
          return unless Homebrew::EnvConfig.update_to_tag?

          puts "To fully enable developer mode, you must unset #{Tty.bold}HOMEBREW_UPDATE_TO_TAG#{Tty.reset}."
        end
      end
    end
  end
end
