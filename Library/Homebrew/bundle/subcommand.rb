# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "bundle/extensions/extension"
require "cli/parser"
require "env_config"
require "etc"
require "bundle/subcommand_context"
require "utils/output"

Dir["#{__dir__}/subcommand/*.rb"].each do |subcommand|
  require "bundle/subcommand/#{File.basename(subcommand, ".rb")}"
end

module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      extend Utils::Output::Mixin

      class << self
        sig {
          params(
            args:       T.untyped,
            extensions: T::Array[T.class_of(Homebrew::Bundle::Extension)],
          ).void
        }
        def dispatch(args, extensions:)
          ask = Homebrew::EnvConfig.ask?

          # Don't want to ask for input in Bundle
          ENV["HOMEBREW_ASK"] = nil
          ENV["HOMEBREW_NO_ASK"] = "1"

          Homebrew::EnvConfig.bundle_dump_describe? unless args.describe?

          context = context(args, extensions:, ask:)
          Homebrew::Bundle.upgrade_formulae = args.upgrade_formulae

          if args.install?
            redirect_stdout($stderr) do
              InstallSubcommand.new(args, context:, quiet: true, cleanup: false).run
            end
          end

          subcommand_class = Homebrew::AbstractSubcommand.subcommands_for(Homebrew::Cmd::Bundle).find do |candidate|
            candidate.subcommand_name == context.subcommand
          end
          raise UsageError, "Unknown subcommand: #{context.subcommand}" unless subcommand_class

          subcommand_class.new(args, context:).run
        end

        sig {
          params(
            args:       T.untyped,
            extensions: T::Array[T.class_of(Homebrew::Bundle::Extension)],
            ask:        T::Boolean,
          ).returns(SubcommandContext)
        }
        def context(args, extensions:, ask: false)
          subcommand = T.let(args.subcommand || "install", String)
          jobs_arg = args.jobs || Homebrew::EnvConfig.bundle_jobs
          jobs = if jobs_arg == "auto"
            [Etc.nprocessors, 4].min
          else
            jobs_arg&.to_i || 1
          end
          no_upgrade = if args.upgrade?
            false
          else
            args.no_upgrade?.present?
          end

          SubcommandContext.new(
            subcommand:,
            global:       args.global?,
            file:         args.file,
            no_upgrade:,
            verbose:      args.verbose?,
            force:        args.force?,
            ask:,
            jobs:         [jobs, 1].max,
            zap:          args.zap?,
            no_type_args: no_type_args?(args, extensions:),
            extensions:,
          )
        end

        sig {
          params(
            args:       T.untyped,
            extensions: T::Array[T.class_of(Homebrew::Bundle::Extension)],
          ).returns(T::Boolean)
        }
        def no_type_args?(args, extensions:)
          ([args.formulae?, args.casks?, args.taps?] +
            extensions.map { |extension| args.public_send(extension.predicate_method) }).none?
        end
      end
    end
  end
end
