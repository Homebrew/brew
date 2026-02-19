# typed: strict
# frozen_string_literal: true

require "github_runner"

class DependentShardMatrix
  MIN_SHARD_COUNT = 1
  private_constant :MIN_SHARD_COUNT
  SHARD_RUNNER_LOAD_FACTOR_MIN = 0.0
  SHARD_RUNNER_LOAD_FACTOR_MAX = 1.0

  sig { params(value: Float).returns(T::Boolean) }
  def self.valid_shard_runner_load_factor?(value)
    value > SHARD_RUNNER_LOAD_FACTOR_MIN && value <= SHARD_RUNNER_LOAD_FACTOR_MAX
  end

  sig {
    params(
      active_runners:                  T::Array[GitHubRunner],
      dependent_count_by_runner:       T::Hash[GitHubRunner, Integer],
      shard_max_runners:               Integer,
      shard_min_dependents_per_runner: Integer,
      shard_runner_load_factor:        Float,
    ).void
  }
  def initialize(active_runners:, dependent_count_by_runner:, shard_max_runners:, shard_min_dependents_per_runner:,
                 shard_runner_load_factor:)
    if shard_max_runners < MIN_SHARD_COUNT
      raise ArgumentError, "shard_max_runners must be an integer greater than or equal to #{MIN_SHARD_COUNT}."
    end

    if shard_min_dependents_per_runner < MIN_SHARD_COUNT
      raise ArgumentError,
            "shard_min_dependents_per_runner must be an integer greater than or equal to #{MIN_SHARD_COUNT}."
    end

    unless self.class.valid_shard_runner_load_factor?(shard_runner_load_factor)
      raise ArgumentError,
            "shard_runner_load_factor must be greater than #{SHARD_RUNNER_LOAD_FACTOR_MIN} and less than or equal " \
            "to #{SHARD_RUNNER_LOAD_FACTOR_MAX}."
    end

    @active_runners = active_runners
    @dependent_count_by_runner = dependent_count_by_runner
    @shard_max_runners = shard_max_runners
    @shard_min_dependents_per_runner = shard_min_dependents_per_runner
    @shard_runner_load_factor = shard_runner_load_factor
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def runner_specs_hash
    @active_runners.flat_map do |runner|
      shard_count = shard_count_for_runner(runner)
      expanded_spec_rows(runner.spec.to_h, shard_count)
    end
  end

  private

  sig { params(spec_hash: T::Hash[Symbol, T.untyped], shard_count: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def expanded_spec_rows(spec_hash, shard_count)
    (1..shard_count).map do |shard_index|
      spec_hash.merge(
        dependent_shard_count: shard_count,
        dependent_shard_index: shard_index,
      )
    end
  end

  sig { params(runner: GitHubRunner).returns(Integer) }
  def shard_count_for_runner(runner)
    dependent_count = @dependent_count_by_runner.fetch(runner, 0)
    # The load factor allows activating extra shards when they are close to the configured minimum.
    effective_min_dependents = @shard_min_dependents_per_runner * @shard_runner_load_factor
    shard_count = (dependent_count / effective_min_dependents).floor
    # Keep a single shard so dependents never disappear from the matrix.
    shard_count = MIN_SHARD_COUNT if shard_count < MIN_SHARD_COUNT
    [shard_count, @shard_max_runners].min
  end
end
