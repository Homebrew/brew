# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "test_runner_formula"
require "github_runner_matrix"

module Homebrew
  module DevCmd
    class DetermineTestRunners < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `determine-test-runners` {<testing-formulae> [<deleted-formulae>]|--all-supported}

          Determines the runners used to test formulae or their dependents. For internal use in Homebrew taps.
        EOS
        switch "--all-supported",
               description: "Instead of selecting runners based on the chosen formula, return all supported runners."
        switch "--eval-all",
               description: "Evaluate all available formulae, whether installed or not, to determine testing " \
                            "dependents.",
               env:         :eval_all
        switch "--dependents",
               description: "Determine runners for testing dependents. Requires `--eval-all` or `HOMEBREW_EVAL_ALL`.",
               depends_on:  "--eval-all"

        named_args max: 2

        conflicts "--all-supported", "--dependents"

        hide_from_man_page!
      end

      sig { override.void }
      def run
        if args.no_named? && !args.all_supported?
          raise Homebrew::CLI::MinNamedArgumentsError, 1
        elsif args.all_supported? && !args.no_named?
          raise UsageError, "`--all-supported` is mutually exclusive to other arguments."
        end

        testing_formulae = args.named.first&.split(",").to_a.map do |name|
          TestRunnerFormula.new(Formulary.factory(name), eval_all: args.eval_all?)
        end.freeze
        deleted_formulae = args.named.second&.split(",").to_a.freeze
        runner_matrix = GitHubRunnerMatrix.new(testing_formulae, deleted_formulae,
                                               all_supported:    args.all_supported?,
                                               dependent_matrix: args.dependents?)
        runners = runner_matrix.active_runner_specs_hash

        ohai "Runners", JSON.pretty_generate(runners)

        github_output = ENV.fetch("GITHUB_OUTPUT")
        File.open(github_output, "a") do |f|
          f.puts("runners=#{runners.to_json}")
          f.puts("runners_present=#{runners.present?}")
        end
      end
    end
  end
end
