# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "services/cli"
require "services/system"
require "services/commands/list"

module Homebrew
  module Cmd
    class Services < AbstractCommand
      include TargetableCommand
      include AbstractSubcommandMod
      include SubcommandDispatcher

      cmd_args do
        usage_banner <<~EOS
          `services` [<subcommand>]

          Manage background services with macOS' `launchctl`(1) daemon manager or
          Linux's `systemctl`(1) service manager.

          If `sudo` is passed, operate on `/Library/LaunchDaemons` or `/usr/lib/systemd/system`  (started at boot).
          Otherwise, operate on `~/Library/LaunchAgents` or `~/.config/systemd/user` (started at login).

          [`sudo`] `brew services` [`list`] (`--json`) (`--debug`):
          List information about all managed services for the current user (or root).
          Provides more output from Homebrew and `launchctl`(1) or `systemctl`(1) if run with `--debug`.

          [`sudo`] `brew services info` (<formula>|`--all`|`--json`):
          List all managed services for the current user (or root).

          [`sudo`] `brew services run` (<formula>|`--all`|`--file=`):
          Run the service <formula> without registering to launch at login (or boot).

          [`sudo`] `brew services start` (<formula>|`--all`|`--file=`):
          Start the service <formula> immediately and register it to launch at login (or boot).

          [`sudo`] `brew services stop` (`--keep`) (`--no-wait`|`--max-wait=`) (<formula>|`--all`):
          Stop the service <formula> immediately and unregister it from launching at login (or boot),
          unless `--keep` is specified.

          [`sudo`] `brew services kill` (<formula>|`--all`):
          Stop the service <formula> immediately but keep it registered to launch at login (or boot).

          [`sudo`] `brew services restart` (<formula>|`--all`|`--file=`):
          Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).

          [`sudo`] `brew services cleanup`:
          Remove all unused services.
        EOS
        flag "--file=", description: "Use the service file from this location to `start` the service."
        flag "--sudo-service-user=", description: "When run as root on macOS, run the service(s) as this user."
        flag "--max-wait=", description: "Wait at most this many seconds for `stop` to finish stopping a service. " \
                                         "Omit this flag or set this to zero (0) seconds to wait indefinitely."
        switch "--all", description: "Run <subcommand> on all services."
        switch "--json", description: "Output as JSON."
        switch "--no-wait", description: "Don't wait for `stop` to finish stopping the service."
        switch "--keep", description: "When stopped, don't unregister the service from launching at login (or boot)."
        conflicts "--max-wait=", "--no-wait"
        named_args %w[list info run start stop kill restart cleanup]
      end

      sig { returns(T.proc.params(parser: CLI::Parser).void) }
      def self.shared_args_block
        proc do |parser|
          parser.flag "--file=", description: "Use the service file from this location to `start` the service."
          parser.switch "--all", description: "Run on all services."
          parser.switch "--json", description: "Output as JSON."
          parser.switch "--verbose", description: "Output more detailed information."
        end
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
          raise UsageError,
                "`brew services` is supported only on macOS or Linux (with systemd)!"
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

        if Homebrew::Services::System.systemctl?
          ENV["DBUS_SESSION_BUS_ADDRESS"] = ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)
          ENV["XDG_RUNTIME_DIR"] = ENV.fetch("HOMEBREW_XDG_RUNTIME_DIR", nil)
        end

        dispatch_subcommand(args.named.first.presence) || default_subcommand
      end

      sig { void }
      def default_subcommand
        args_obj = T.unsafe(args)
        Homebrew::Services::Commands::List.run(json: args_obj.respond_to?(:json?) ? args_obj.json? : false)
      end

      class ListSubcommand < AbstractSubcommand
        cmd_args do
          switch "--json", description: "Output as JSON."
        end

        sig { override.void }
        def run
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::List.run(json: args_obj.respond_to?(:json?) ? args_obj.json? : false)
        end
      end

      class InfoSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          switch "--json", description: "Output as JSON."
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
        end

        sig { override.void }
        def run
          targets = get_targets
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Info.run(
            targets,
            verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
            json:    args_obj.respond_to?(:json?) ? args_obj.json? : false,
          )
        end
      end

      class CleanupSubcommand < AbstractSubcommand
        sig { override.void }
        def run
          Homebrew::Services::Commands::Cleanup.run
        end
      end

      class RestartSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          flag "--file=", description: "Use the service file from this location to `start` the service."
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
        end

        sig { override.void }
        def run
          targets = get_targets
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Restart.run(
            targets,
            args_obj.respond_to?(:file) ? args_obj.file : nil,
            verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
          )
        end
      end

      class RunSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          flag "--file=", description: "Use the service file from this location to `start` the service."
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
        end

        sig { override.void }
        def run
          targets = get_targets
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Run.run(
            targets,
            args_obj.respond_to?(:file) ? args_obj.file : nil,
            verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
          )
        end
      end

      class StartSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          flag "--file=", description: "Use the service file from this location to `start` the service."
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
        end

        sig { override.void }
        def run
          targets = get_targets(loaded: false)
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Start.run(
            targets,
            args_obj.respond_to?(:file) ? args_obj.file : nil,
            verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
          )
        end
      end

      class StopSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
          switch "--keep",
                 description: "When stopped, don't unregister the service from launching at login (or boot)."
          switch "--no-wait", description: "Don't wait for `stop` to finish stopping the service."
          flag "--max-wait=",
               description: "Wait at most this many seconds for `stop` to finish stopping a service. " \
                            "Omit this flag or set this to zero (0) seconds to wait indefinitely."
          conflicts "--max-wait=", "--no-wait"
        end

        sig { override.void }
        def run
          targets = get_targets(loaded: true)
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Stop.run(
            targets,
            verbose:  args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
            no_wait:  args_obj.respond_to?(:no_wait?) ? args_obj.no_wait? : false,
            max_wait: (args_obj.respond_to?(:max_wait) && args_obj.max_wait) ? args_obj.max_wait.to_f : 0.0,
            keep:     args_obj.respond_to?(:keep?) ? args_obj.keep? : false,
          )
        end
      end

      class KillSubcommand < AbstractSubcommand
        include TargetableCommand

        cmd_args do
          switch "--verbose", description: "Output more detailed information."
          switch "--all", description: "Run on all services."
        end

        sig { override.void }
        def run
          targets = get_targets
          args_obj = T.unsafe(args)
          Homebrew::Services::Commands::Kill.run(
            targets,
            verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
          )
        end
      end
    end
  end
end
