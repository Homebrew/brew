# typed: strict
# frozen_string_literal: true

require "abstract_command"

module DinrusBrew
  module Cmd
    class Developer < AbstractCommand
      cmd_args do
        description <<~EOS
          Control DinrusBrew's developer mode. When developer mode is enabled,
          `brew update` will update DinrusBrew to the latest commit on the `master`
          branch instead of the latest stable version along with some other behaviour changes.

          `brew developer` [`state`]:
          Display the current state of DinrusBrew's developer mode.

          `brew developer` (`on`|`off`):
          Turn DinrusBrew's developer mode on or off respectively.
        EOS

        named_args %w[state on off], max: 1
      end

      sig { override.void }
      def run
        case args.named.first
        when nil, "state"
          if DinrusBrew::EnvConfig.developer?
            puts "Developer mode is enabled because #{Tty.bold}DINRUSBREW_DEVELOPER#{Tty.reset} is set."
          elsif DinrusBrew::EnvConfig.devcmdrun?
            puts "Developer mode is enabled because a developer command or `brew developer on` was run."
          else
            puts "Developer mode is disabled."
          end
          if DinrusBrew::EnvConfig.developer? || DinrusBrew::EnvConfig.devcmdrun?
            if DinrusBrew::EnvConfig.update_to_tag?
              puts "However, `brew update` will update to the latest stable tag because " \
                   "#{Tty.bold}DINRUSBREW_UPDATE_TO_TAG#{Tty.reset} is set."
            else
              puts "`brew update` will update to the latest commit on the `master` branch."
            end
          else
            puts "`brew update` will update to the latest stable tag."
          end
        when "on"
          DinrusBrew::Settings.write "devcmdrun", true
          if DinrusBrew::EnvConfig.update_to_tag?
            puts "To fully enable developer mode, you must unset #{Tty.bold}DINRUSBREW_UPDATE_TO_TAG#{Tty.reset}."
          end
        when "off"
          DinrusBrew::Settings.delete "devcmdrun"
          if DinrusBrew::EnvConfig.developer?
            puts "To fully disable developer mode, you must unset #{Tty.bold}DINRUSBREW_DEVELOPER#{Tty.reset}."
          end
        else
          raise UsageError, "unknown subcommand: #{args.named.first}"
        end
      end
    end
  end
end
