# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "services/system"
require "services/commands/list"
require "services/commands/cleanup"
require "services/commands/info"
require "services/commands/restart"
require "services/commands/run"
require "services/commands/start"
require "services/commands/stop"
require "services/commands/kill"

module Homebrew
  module Cmd
    class Services < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `services` [<subcommand>]

          Manage background services with macOS' `launchctl`(1) daemon manager or
          Linux's `systemctl`(1) service manager.

          If `sudo` is passed, operate on `/Library/LaunchDaemons` or `/usr/lib/systemd/system` (started at boot).
          Otherwise, operate on `~/Library/LaunchAgents` or `~/.config/systemd/user` (started at login).

          [`sudo`] `brew services` [`list`] [`--json`] [`--debug`]:
          List information about all managed services for the current user (or root).
          Provides more output from Homebrew and `launchctl`(1) or `systemctl`(1) if run with `--debug`.

          [`sudo`] `brew services info` (<formula>|`--all`) [`--json`]:
          List all managed services for the current user (or root).

          [`sudo`] `brew services run` (<formula>|`--all`) [`--file=`]:
          Run the service <formula> without registering to launch at login (or boot).

          [`sudo`] `brew services start` (<formula>|`--all`) [`--file=`]:
          Start the service <formula> immediately and register it to launch at login (or boot).

          [`sudo`] `brew services stop` [`--keep`] [`--no-wait`|`--max-wait=`] (<formula>|`--all`):
          Stop the service <formula> immediately and unregister it from launching at login (or boot),
          unless `--keep` is specified.

          [`sudo`] `brew services kill` (<formula>|`--all`):
          Stop the service <formula> immediately but keep it registered to launch at login (or boot).

          [`sudo`] `brew services restart` (<formula>|`--all`) [`--file=`]:
          Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).

          [`sudo`] `brew services cleanup`:
          Remove all unused services.
        EOS
        flag   "--file=",
               description: "Use the service file from this location to `start` the service."
        flag   "--sudo-service-user=",
               description: "When run as root on macOS, run the service(s) as this user."
        flag   "--max-wait=",
               description: "Wait at most this many seconds for `stop` to finish stopping a service. " \
                            "Defaults to 60. Set this to zero (0) seconds to wait indefinitely."
        switch "--no-wait",
               description: "Don't wait for `stop` to finish stopping the service."
        switch "--keep",
               description: "When stopped, don't unregister the service from launching at login (or boot)."
        switch "--all",
               description: "Run <subcommand> on all services."
        switch "--json",
               description: "Output as JSON."

        conflicts "--all", "--file"
        conflicts "--max-wait", "--no-wait"

        named_args %w[list info run start stop kill restart cleanup]
      end

      sig { override.void }
      def run
        # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
        if ENV.fetch("HOMEBREW_TMUX", nil) && File.exist?("/usr/bin/pbpaste") && !quiet_system("/usr/bin/pbpaste")
          raise UsageError,
                "`brew services` cannot run under tmux!"
        end

        # Keep this after the .parse to keep --help fast.
        require "utils"

        if !Homebrew::Services::System.launchctl? && !Homebrew::Services::System.systemctl?
          raise UsageError, Homebrew::Services::System::MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE
        end

        if (sudo_service_user = args.sudo_service_user)
          unless Homebrew::Services::System.root?
            raise UsageError,
                  "`brew services` is supported only when running as root!"
          end

          unless Homebrew::Services::System.launchctl?
            raise UsageError,
                  "`brew services --sudo-service-user` is currently supported only on macOS " \
                  "(but we'd love a PR to add Linux support)!"
          end

          Homebrew::Services::Cli.sudo_service_user = sudo_service_user
        end

        # Parse arguments.
        subcommand, *formulae = args.named

        no_named_formula_commands = [
          *Homebrew::Services::Commands::List::TRIGGERS,
          *Homebrew::Services::Commands::Cleanup::TRIGGERS,
        ]
        if no_named_formula_commands.include?(subcommand)
          raise UsageError, "The `#{subcommand}` subcommand does not accept a formula argument!" if formulae.present?
          raise UsageError, "The `#{subcommand}` subcommand does not accept the `--all` argument!" if args.all?
        end

        if args.file
          file_commands = [
            *Homebrew::Services::Commands::Start::TRIGGERS,
            *Homebrew::Services::Commands::Run::TRIGGERS,
            *Homebrew::Services::Commands::Restart::TRIGGERS,
          ]
          if file_commands.exclude?(subcommand)
            raise UsageError, "The `#{subcommand}` subcommand does not accept the `--file=` argument!"
          end
        end

        unless Homebrew::Services::Commands::Stop::TRIGGERS.include?(subcommand)
          raise UsageError, "The `#{subcommand}` subcommand does not accept the `--keep` argument!" if args.keep?

          if args.no_wait?
            raise UsageError, "The `#{subcommand}` subcommand does not accept the `--no-wait` argument!"
          end
          if args.max_wait
            raise UsageError, "The `#{subcommand}` subcommand does not accept the `--max-wait=` argument!"
          end
        end

        opoo "The `--all` argument overrides provided formula argument!" if formulae.present? && args.all?

        targets = if args.all?
          if subcommand == "start"
            Homebrew::Services::Formulae.available_services(
              loaded:    false,
              skip_root: !Homebrew::Services::System.root?,
            )
          elsif subcommand == "stop"
            Homebrew::Services::Formulae.available_services(
              loaded:    true,
              skip_root: !Homebrew::Services::System.root?,
            )
          else
            Homebrew::Services::Formulae.available_services
          end
        elsif formulae.present?
          formulae.map { |formula| Homebrew::Services::FormulaWrapper.new(Formulary.factory(formula)) }
        else
          []
        end

        # Exit successfully if --all was used but there is nothing to do
        return if args.all? && targets.empty?

        if Homebrew::Services::System.systemctl?
          ENV["DBUS_SESSION_BUS_ADDRESS"] = ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)
          ENV["XDG_RUNTIME_DIR"] = ENV.fetch("HOMEBREW_XDG_RUNTIME_DIR", nil)
        end

        # Dispatch commands and aliases.
        case subcommand.presence
        when *Homebrew::Services::Commands::List::TRIGGERS
          Homebrew::Services::Commands::List.run(json: args.json?)
        when *Homebrew::Services::Commands::Cleanup::TRIGGERS
          Homebrew::Services::Commands::Cleanup.run
        when *Homebrew::Services::Commands::Info::TRIGGERS
          Homebrew::Services::Commands::Info.run(targets, verbose: args.verbose?, json: args.json?)
        when *Homebrew::Services::Commands::Restart::TRIGGERS
          Homebrew::Services::Commands::Restart.run(targets, args.file, verbose: args.verbose?)
        when *Homebrew::Services::Commands::Run::TRIGGERS
          Homebrew::Services::Commands::Run.run(targets, args.file, verbose: args.verbose?)
        when *Homebrew::Services::Commands::Start::TRIGGERS
          Homebrew::Services::Commands::Start.run(targets, args.file, verbose: args.verbose?)
        when *Homebrew::Services::Commands::Stop::TRIGGERS
          Homebrew::Services::Commands::Stop.run(
            targets,
            verbose:  args.verbose?,
            no_wait:  args.no_wait?,
            max_wait: args.max_wait&.to_f || 60.0,
            keep:     args.keep?,
          )
        when *Homebrew::Services::Commands::Kill::TRIGGERS
          Homebrew::Services::Commands::Kill.run(targets, verbose: args.verbose?)
        else
          raise UsageError, "unknown subcommand: `#{subcommand}`"
        end
      end
    end
  end
end
