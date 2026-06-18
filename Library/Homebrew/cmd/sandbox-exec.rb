# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "sandbox"

module Homebrew
  module Cmd
    class SandboxExec < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `sandbox-exec` [`--deny-network`] <writable-path> [`--`] <command> [<args> ...]

          Run <command> in Homebrew's sandbox, allowing writes to <writable-path> and
          Homebrew's temporary and cache directories.

          Example: `brew sandbox-exec . -- make test`
        EOS

        switch "--deny-network",
               description: "Deny network access from inside the sandbox."

        named_args min: 2
      end

      sig { override.void }
      def run
        writable_path = args.named.first
        raise UsageError, "`sandbox-exec` requires a writable path." unless writable_path

        Sandbox.run_command(
          *args.named.drop(1),
          writable_path:,
          deny_network:  args.deny_network?,
        )
      end
    end
  end
end
