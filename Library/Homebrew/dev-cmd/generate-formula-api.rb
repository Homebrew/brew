# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "api/generator"

module Homebrew
  module DevCmd
    class GenerateFormulaApi < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate `homebrew/core` API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS
        switch "-n", "--dry-run",
               description: "Generate API data without writing it to files."

        named_args :none
      end

      sig { override.void }
      def run
        # odeprecated "brew generate-formula-api", "brew generate-package-api --only-core"

        Homebrew::API::Generator.new(
          only_core: true,
          dry_run:   args.dry_run?,
        ).generate!
      end
    end
  end
end
