# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "test_runner_formula"
require "github_runner_matrix"
require "sharded_runner_matrix"

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
               description: "Determine runners for testing dependents. " \
                            "Requires `--eval-all` or `HOMEBREW_EVAL_ALL=1` to be set.",
               depends_on:  "--eval-all"
        flag "--dependent-shard-max-runners=",
             description: "Maximum number of dependent shards per active runner when using `--dependents`.",
             depends_on:  "--dependents"
        flag "--dependent-shard-min-dependents-per-runner=",
             description: "Minimum number of dependent formulae per shard when using `--dependents`.",
             depends_on:  "--dependents"
        flag "--dependent-shard-runner-load-factor=",
             description: "Minimum load ratio per shard (0,1] used when expanding dependent shards.",
             depends_on:  "--dependents"

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

        shard_max_runners = dependent_shard_max_runners_value
        shard_min_items_per_runner = dependent_shard_min_dependents_per_runner_value
        shard_runner_load_factor = dependent_shard_runner_load_factor_value

        testing_formulae = args.named.first&.split(",").to_a.map do |name|
          TestRunnerFormula.new(Formulary.factory(name), eval_all: args.eval_all?)
        end.freeze
        deleted_formulae = args.named.second&.split(",").to_a.freeze

        runner_matrix_class = if args.dependents?
          ShardedRunnerMatrix
        else
          GitHubRunnerMatrix
        end
        runner_matrix_args = {
          all_supported:    args.all_supported?,
          dependent_matrix: args.dependents?,
        }
        if args.dependents?
          runner_matrix_args[:shard_max_runners] = shard_max_runners
          runner_matrix_args[:shard_min_items_per_runner] = shard_min_items_per_runner
          runner_matrix_args[:shard_runner_load_factor] = shard_runner_load_factor
          runner_matrix_args[:shard_count_key] = ShardedRunnerMatrix::ShardCountKey::DependentShardCount
          runner_matrix_args[:shard_index_key] = ShardedRunnerMatrix::ShardIndexKey::DependentShardIndex
        end
        runner_matrix = runner_matrix_class.new(testing_formulae, deleted_formulae, **runner_matrix_args)
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

      private

      sig { returns(Integer) }
      def dependent_shard_max_runners_value
        parse_positive_integer_option(
          args.dependent_shard_max_runners,
          "--dependent-shard-max-runners",
          default_value: ShardedRunnerMatrix::DEFAULT_SHARD_MAX_RUNNERS,
        )
      end

      sig { returns(Integer) }
      def dependent_shard_min_dependents_per_runner_value
        parse_positive_integer_option(
          args.dependent_shard_min_dependents_per_runner,
          "--dependent-shard-min-dependents-per-runner",
          default_value: ShardedRunnerMatrix::DEFAULT_SHARD_MIN_ITEMS_PER_RUNNER,
        )
      end

      sig { returns(Float) }
      def dependent_shard_runner_load_factor_value
        parse_load_factor_option(
          args.dependent_shard_runner_load_factor,
          "--dependent-shard-runner-load-factor",
          default_value: ShardedRunnerMatrix::DEFAULT_SHARD_RUNNER_LOAD_FACTOR,
        )
      end

      sig { params(raw_value: T.nilable(String), flag_name: String, default_value: Integer).returns(Integer) }
      def parse_positive_integer_option(raw_value, flag_name, default_value:)
        value = raw_value.presence || default_value.to_s
        parsed_value = T.let(Integer(value, exception: false), T.nilable(Integer))
        return parsed_value if parsed_value && parsed_value >= 1

        raise UsageError, "`#{flag_name}` must be an integer greater than or equal to 1."
      end

      sig { params(raw_value: T.nilable(String), flag_name: String, default_value: Float).returns(Float) }
      def parse_load_factor_option(raw_value, flag_name, default_value:)
        value = raw_value.presence || default_value.to_s
        parsed_value = T.let(Float(value, exception: false), T.nilable(Float))
        return parsed_value if parsed_value && ShardedRunnerMatrix.valid_shard_runner_load_factor?(parsed_value)

        raise UsageError, "`#{flag_name}` must be a number greater than 0 and less than or equal to 1."
      end
    end
  end
end
