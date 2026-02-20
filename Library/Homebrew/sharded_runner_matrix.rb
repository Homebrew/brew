# typed: strict
# frozen_string_literal: true

require "github_runner_matrix"

# Specialized GitHub runner matrix that expands jobs into deterministic shards.
class ShardedRunnerMatrix < GitHubRunnerMatrix
  RunnerSpecHash = T.type_alias { T::Hash[Symbol, T.untyped] }
  private_constant :RunnerSpecHash

  class ShardCountKey < T::Enum
    enums do
      # enum values are not mutable, and calling .freeze on them breaks Sorbet
      # rubocop:disable Style/MutableConstant
      ShardCount = new(:shard_count)
      DependentShardCount = new(:dependent_shard_count)
      # rubocop:enable Style/MutableConstant
    end
  end

  class ShardIndexKey < T::Enum
    enums do
      # enum values are not mutable, and calling .freeze on them breaks Sorbet
      # rubocop:disable Style/MutableConstant
      ShardIndex = new(:shard_index)
      DependentShardIndex = new(:dependent_shard_index)
      # rubocop:enable Style/MutableConstant
    end
  end

  DEFAULT_SHARD_MAX_RUNNERS = 1
  DEFAULT_SHARD_MIN_ITEMS_PER_RUNNER = 200
  DEFAULT_SHARD_RUNNER_LOAD_FACTOR = 1.0
  DEFAULT_SHARD_COUNT_KEY = ShardCountKey::ShardCount
  DEFAULT_SHARD_INDEX_KEY = ShardIndexKey::ShardIndex

  MIN_SHARD_COUNT = 1
  SHARD_RUNNER_LOAD_FACTOR_MIN = 0.0
  SHARD_RUNNER_LOAD_FACTOR_MAX = 1.0

  sig { params(value: Float).returns(T::Boolean) }
  def self.valid_shard_runner_load_factor?(value)
    value > SHARD_RUNNER_LOAD_FACTOR_MIN && value <= SHARD_RUNNER_LOAD_FACTOR_MAX
  end

  sig {
    params(
      testing_formulae:           T::Array[TestRunnerFormula],
      deleted_formulae:           T::Array[String],
      all_supported:              T::Boolean,
      dependent_matrix:           T::Boolean,
      shard_max_runners:          Integer,
      shard_min_items_per_runner: Integer,
      shard_runner_load_factor:   Float,
      shard_count_key:            ShardCountKey,
      shard_index_key:            ShardIndexKey,
    ).void
  }
  def initialize(testing_formulae, deleted_formulae, all_supported:, dependent_matrix: true,
                 shard_max_runners: DEFAULT_SHARD_MAX_RUNNERS,
                 shard_min_items_per_runner: DEFAULT_SHARD_MIN_ITEMS_PER_RUNNER,
                 shard_runner_load_factor: DEFAULT_SHARD_RUNNER_LOAD_FACTOR,
                 shard_count_key: DEFAULT_SHARD_COUNT_KEY,
                 shard_index_key: DEFAULT_SHARD_INDEX_KEY)
    if shard_max_runners < MIN_SHARD_COUNT
      raise ArgumentError, "shard_max_runners must be an integer greater than or equal to 1."
    end
    if shard_min_items_per_runner < MIN_SHARD_COUNT
      raise ArgumentError, "shard_min_items_per_runner must be an integer greater than or equal to 1."
    end
    unless self.class.valid_shard_runner_load_factor?(shard_runner_load_factor)
      raise ArgumentError, "shard_runner_load_factor must be greater than 0 and less than or equal to 1."
    end

    @shard_max_runners = shard_max_runners
    @shard_min_items_per_runner = shard_min_items_per_runner
    @shard_runner_load_factor = shard_runner_load_factor
    @shard_count_key = shard_count_key
    @shard_index_key = shard_index_key

    super(testing_formulae, deleted_formulae, all_supported:, dependent_matrix:)
  end

  sig { override.returns(T::Array[RunnerSpecHash]) }
  def active_runner_specs_hash
    return super unless @dependent_matrix

    active_runners = runners.select(&:active)

    sharded_runner_specs_hash(active_runners)
  end

  private

  sig { params(active_runners: T::Array[GitHubRunner]).returns(T::Array[RunnerSpecHash]) }
  def sharded_runner_specs_hash(active_runners)
    item_count_by_runner = active_runners.to_h do |runner|
      [runner, compatible_matrix_item_names(runner).size]
    end

    active_runners.flat_map do |runner|
      shard_count = shard_count_for_runner(runner, item_count_by_runner)
      expanded_spec_rows(runner.spec.to_h, shard_count)
    end
  end

  sig {
    params(
      runner:               GitHubRunner,
      item_count_by_runner: T::Hash[GitHubRunner, Integer],
    ).returns(Integer)
  }
  def shard_count_for_runner(runner, item_count_by_runner)
    item_count = item_count_by_runner.fetch(runner, 0)
    effective_min_items = @shard_min_items_per_runner * @shard_runner_load_factor
    shard_count = (item_count / effective_min_items).floor
    shard_count = MIN_SHARD_COUNT if shard_count < MIN_SHARD_COUNT
    [shard_count, @shard_max_runners].min
  end

  sig { params(spec_hash: RunnerSpecHash, shard_count: Integer).returns(T::Array[RunnerSpecHash]) }
  def expanded_spec_rows(spec_hash, shard_count)
    (1..shard_count).map do |shard_index|
      spec_hash.merge(
        @shard_count_key.serialize => shard_count,
        @shard_index_key.serialize => shard_index,
      )
    end
  end
end
