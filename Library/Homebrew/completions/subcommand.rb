# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "cli/parser"

Dir["#{__dir__}/subcommand/*.rb"].each do |subcommand|
  require "completions/subcommand/#{File.basename(subcommand, ".rb")}"
end

module Homebrew
  module Cmd
    class CompletionsCmd < Homebrew::AbstractCommand
      class << self
        sig { params(args: T.untyped).void }
        def dispatch(args)
          subcommand_class = Homebrew::AbstractSubcommand
                             .subcommands_for(Homebrew::Cmd::CompletionsCmd)
                             .find do |candidate|
            candidate.subcommand_name == args.subcommand
          end
          raise UsageError, "Unknown `brew completions` subcommand: #{args.subcommand}" if subcommand_class.nil?

          subcommand_class.new(args).run
        end
      end
    end
  end
end
