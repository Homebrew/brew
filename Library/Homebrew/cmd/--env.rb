# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "extend/ENV"
require "build_environment"
require "utils/shell"

module Homebrew
  module Cmd
    class Env < AbstractCommand
      sig { override.returns(String) }
      def self.command_name = "--env"

      cmd_args do
        description <<~EOS
          Summarise Homebrew's build environment as a plain list.

          If the command's output is sent through a pipe and no shell is specified,
          the list is formatted for export to `bash`(1) unless `--plain` is passed.
        EOS
        flag   "--shell=",
               description: "Generate a list of environment variables for the specified shell, " \
                            "or `--shell=auto` to detect the current shell."
        switch "--plain",
               description: "Generate plain output even when piped."

        named_args :formula
      end

      sig { override.void }
      def run
        ENV.activate_extensions!
        ENV.deps = args.named.to_formulae if superenv?(nil)
        ENV.setup_build_environment

        shell = if args.plain?
          nil
        elsif args.shell.nil?
          :bash unless $stdout.tty?
        elsif args.shell == "auto"
          Utils::Shell.parent || Utils::Shell.preferred
        elsif args.shell
          Utils::Shell.from_path(T.must(args.shell))
        end

        if shell.nil?
          BuildEnvironment.dump ENV.to_h
        else
          BuildEnvironment.keys(ENV.to_h).each do |key|
            puts Utils::Shell.export_value(key, ENV.fetch(key), shell)
          end
        end
      end
    end
  end
end
