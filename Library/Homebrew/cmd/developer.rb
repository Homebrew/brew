# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Developer < AbstractCommand
      cmd_args do
        description <<~EOS
          Control Homebrew's developer mode. When developer mode is enabled,
          `brew update` will update Homebrew to the latest commit on the `master`
          branch instead of the latest stable version along with some other behaviour changes.

          `brew developer` [`state`]:
          Display the current state of Homebrew's developer mode.

          `brew developer` (`on`|`off`):
          Turn Homebrew's developer mode on or off respectively.
        EOS

        named_args %w[state on off], max: 1
      end

      sig { override.void }
      def run
        case args.named.first
        when nil, "state"
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
              puts "`brew update` will update to the latest commit on the `master` branch."
            end
          else
            puts "`brew update` will update to the latest stable tag."
          end
        when "on"
          Homebrew::Settings.write "devcmdrun", true
          if Homebrew::EnvConfig.update_to_tag?
            puts "To fully enable developer mode, you must unset #{Tty.bold}HOMEBREW_UPDATE_TO_TAG#{Tty.reset}."
          end
        when "off"
          Homebrew::Settings.delete "devcmdrun"
          if Homebrew::EnvConfig.developer?
            puts "To fully disable developer mode, you must unset #{Tty.bold}HOMEBREW_DEVELOPER#{Tty.reset}."
          end
        else
          raise UsageError, "unknown subcommand: #{args.named.first}"
        end
      end
    end
  end
end
