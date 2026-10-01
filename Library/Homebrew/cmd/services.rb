# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Services < AbstractCommand
      require "services/subcommand"

      cmd_args do
        usage_banner <<~EOS
          `services` [<subcommand>]

          Manage background services with macOS' `launchctl`(1) daemon manager or
          Linux's `systemctl`(1) service manager.

          If `sudo` is passed, operate on `/Library/LaunchDaemons` or `/usr/lib/systemd/system` (started at boot).
          Otherwise, operate on `~/Library/LaunchAgents` or `~/.config/systemd/user` (started at login).

          Environment variables can be added or overridden for a service by creating
          `$HOMEBREW_USER_CONFIG_HOME/services/<formula>.env` (defaults to
          `~/.homebrew/services/<formula>.env`). The file uses `KEY=value`
          format, one per line; lines starting with `#` are comments. Changes take
          effect on the next `brew services restart` and persist across upgrades.
        EOS
        flag   "--sudo-service-user=",
               description: "When run as root on macOS, run the service(s) as this user."

        Homebrew::AbstractSubcommand.define_all(self, command: Homebrew::Cmd::Services)

        conflicts "--all", "--file"
        conflicts "--max-wait", "--no-wait"
      end

      sig { override.void }
      def run
        Homebrew::Cmd::Services.dispatch(args)
      end
    end
  end
end
