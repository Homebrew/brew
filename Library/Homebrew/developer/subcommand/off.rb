# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "env_config"
require "settings"
require "utils/tty"

module Homebrew
  module Cmd
    class Developer < Homebrew::AbstractCommand
      class OffSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew developer off`:
            Turn Homebrew's developer mode off.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Homebrew::Settings.delete "devcmdrun"
          return unless Homebrew::EnvConfig.developer?

          puts "To fully disable developer mode, you must unset #{Tty.bold}HOMEBREW_DEVELOPER#{Tty.reset}."
        end
      end
    end
  end
end
