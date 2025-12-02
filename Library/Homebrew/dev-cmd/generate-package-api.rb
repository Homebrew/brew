# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "api/generator"

module Homebrew
  module DevCmd
    class GeneratePackageApi < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS
        switch "--only-core",
               description: "Only generate API data for packages in `homebrew/core`."
        switch "--only-cask",
               description: "Only generate API data for packages in `homebrew/cask`."
        switch "--only-packages",
               description: "Only generate the combined packages API data."
        switch "-n", "--dry-run",
               description: "Generate API data without writing it to files."

        conflicts "--only-core", "--only-cask", "--only-packages"

        named_args :none
      end

      sig { override.void }
      def run
        Homebrew::API::Generator.new(
          only_core:     args.only_core?,
          only_cask:     args.only_cask?,
          only_packages: args.only_packages?,
          dry_run:       args.dry_run?,
        ).generate!
      end
    end
  end
end
