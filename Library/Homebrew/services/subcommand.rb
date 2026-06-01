# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "cli/parser"
require "services/cli"
require "services/formulae"
require "services/system"
require "utils/output"

Dir["#{__dir__}/subcommand/*.rb"].each do |subcommand|
  require "services/subcommand/#{File.basename(subcommand, ".rb")}"
end

module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      extend Utils::Output::Mixin

      class << self
        sig { params(args: T.untyped).void }
        def dispatch(args)
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
                    "`brew services --sudo-service-user` is supported only when running as root!"
            end

            unless Homebrew::Services::System.launchctl?
              raise UsageError,
                    "`brew services --sudo-service-user` is currently supported only on macOS " \
                    "(but we'd love a PR to add Linux support)!"
            end

            Homebrew::Services::Cli.sudo_service_user = sudo_service_user
          end

          subcommand = args.subcommand
          formulae = args.named

          opoo "The `--all` argument overrides provided formula argument!" if formulae.present? && args.all?

          targets = targets(args, subcommand:, formulae:)

          # Exit successfully if --all was used but there is nothing to do
          return if args.all? && targets.empty?

          if Homebrew::Services::System.systemctl?
            ENV["DBUS_SESSION_BUS_ADDRESS"] = ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)
            ENV["XDG_RUNTIME_DIR"] = ENV.fetch("HOMEBREW_XDG_RUNTIME_DIR", nil)
          end

          subcommand_class = Homebrew::AbstractSubcommand.subcommands_for(Homebrew::Cmd::Services).find do |candidate|
            candidate.subcommand_name == subcommand
          end
          T.must(subcommand_class).new(args, targets:).run
        end

        sig {
          params(args: T.untyped, subcommand: String,
                 formulae: T::Array[String]).returns(T::Array[Homebrew::Services::FormulaWrapper])
        }
        def targets(args, subcommand:, formulae:)
          if args.all?
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
        end
      end
    end
  end
end
