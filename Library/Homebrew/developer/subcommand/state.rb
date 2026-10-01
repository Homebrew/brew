# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "env_config"
require "utils/tty"

module Homebrew
  module Cmd
    class Developer < Homebrew::AbstractCommand
      class StateSubcommand < Homebrew::AbstractSubcommand
        subcommand_args default: true do
          usage_banner <<~EOS
            `brew developer` [`state`]:
            Display the current state of Homebrew's developer mode.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          if Homebrew::EnvConfig.developer?
            puts "Developer mode is enabled because #{Tty.bold}HOMEBREW_DEVELOPER#{Tty.reset} is set."
          elsif Homebrew::EnvConfig.devcmdrun?
            puts "Developer mode is enabled because a developer command or `brew developer on` was run."
          else
            puts "Developer mode is disabled."
          end

          if Homebrew::EnvConfig.developer? || Homebrew::EnvConfig.devcmdrun?
            if Homebrew::EnvConfig.update_to_tag?
              puts "However, `brew update` will update to the latest stable tag because " \
                   "#{Tty.bold}HOMEBREW_UPDATE_TO_TAG#{Tty.reset} is set."
            else
              puts "`brew update` will update to the latest commit on the `main` branch."
            end
          else
            puts "`brew update` will update to the latest stable tag."
          end
        end
      end
    end
  end
end
