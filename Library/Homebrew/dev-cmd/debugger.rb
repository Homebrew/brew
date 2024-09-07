# typed: strict
# frozen_string_literal: true

module Homebrew
  module DevCmd
    class Debugger < AbstractCommand
      cmd_args do
        description <<~EOS
          Run the specified Homebrew command in debug mode.

          To pass flags to the command, use `--` to separate them from the `brew` flags.
          For example: `brew debugger -- list --formula`.
        EOS
        switch "-O", "--open",
               description: "Start remote debugging over a Unix socket."

        named_args :command, min: 1
      end

      sig { override.void }
      def run
        raise UsageError, "Debugger is only supported with portable Ruby!" unless HOMEBREW_USING_PORTABLE_RUBY

        unless Commands.valid_ruby_cmd?(args.named.first)
          raise UsageError, "`#{args.named.first}` is not a valid Ruby command!"
        end

        brew_rb = (HOMEBREW_LIBRARY_PATH/"brew.rb").resolved_path
        debugger_method = if args.open?
          "open"
        else
          "start"
        end

        env = {}
        env[:RUBY_DEBUG_FORK_MODE] = "parent"
        env[:RUBY_DEBUG_NONSTOP] = "1" unless ENV["HOMEBREW_RDBG"]

        with_env(**env) do
          system(*HOMEBREW_RUBY_EXEC_ARGS,
                 "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
                 "-rdebug/#{debugger_method}",
                 brew_rb, *args.named)
        end
      end
    end
  end
end
