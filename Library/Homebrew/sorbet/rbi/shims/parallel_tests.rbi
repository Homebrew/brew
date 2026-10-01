# typed: strict

module ParallelTests
  module RSpec
    class Runner
      sig {
        params(
          tests:      T::Array[String],
          num_groups: Integer,
          options:    T::Hash[Symbol, String],
        ).returns(T::Array[T::Array[String]])
      }
      def self.tests_in_groups(tests, num_groups, options = {}); end
    end
  end
end
