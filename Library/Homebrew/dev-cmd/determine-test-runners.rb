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
               env:         :eval_all,
               odeprecated: true
        switch "--dependents",
               description: "Determine runners for testing dependents."
        flag   "--dependent-shards=",
               description: "Split each dependent runner into the given number of shards.",
               depends_on:  "--dependents",
               hidden:      true

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

        eval_all = args.eval_all?
        eval_all ||= Homebrew::EnvConfig.tap_trust_configured?

        testing_formulae = args.named.first&.split(",").to_a.map do |name|
          TestRunnerFormula.new(Formulary.factory(name), eval_all:)
        end.freeze
        deleted_formulae = args.named.second&.split(",").to_a.freeze
        dependent_shards = args.dependent_shards || "1"
        unless dependent_shards.match?(/\A[1-9]\d*\z/)
          raise UsageError,
                "`--dependent-shards` must be a positive integer."
        end

        runner_matrix = GitHubRunnerMatrix.new(testing_formulae, deleted_formulae,
                                               all_supported:    args.all_supported?,
                                               dependent_matrix: args.dependents?,
                                               dependent_shards: dependent_shards.to_i)
        runners = runner_matrix.active_runner_specs_hash

        ohai "Runners", JSON.pretty_generate(runners)

        # gracefully handle non-GitHub Actions environments
        github_output = if ENV.key?("GITHUB_ACTIONS")
          ENV.fetch("GITHUB_OUTPUT")
        else
          ENV.fetch("GITHUB_OUTPUT", nil)
        end
        return unless github_output

        File.open(github_output, "a") do |f|
          f.puts("runners=#{runners.to_json}")
          f.puts("runners_present=#{runners.present?}")
        end
      end
    end
  end
end
