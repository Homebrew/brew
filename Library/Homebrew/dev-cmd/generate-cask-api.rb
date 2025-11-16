# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/cask"
require "fileutils"
require "formula"

module Homebrew
  module DevCmd
    class GenerateCaskApi < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate `homebrew/cask` API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS
        switch "-n", "--dry-run",
               description: "Generate API data without writing it to files."

        named_args :none
      end

      sig { override.void }
      def run
        Homebrew::API.generate_cask_api!(dry_run: args.dry_run?)
      end
    end
  end
end
