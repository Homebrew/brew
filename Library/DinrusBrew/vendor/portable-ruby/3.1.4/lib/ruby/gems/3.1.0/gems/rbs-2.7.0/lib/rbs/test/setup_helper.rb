# frozen_string_literal: true

module RBS
  module Test
    module SetupHelper
      class InvalidSampleSizeError < StandardError
        attr_reader :string

        def initialize(string)
          @string = string
          super("Sample size should be a positive integer: `#{string}`")
        end
      end

      DEFAULT_SAMPLE_SIZE = 100

      def get_sample_size(string)
        case string
        when ""
          DEFAULT_SAMPLE_SIZE
        when 'ALL'
          nil
        else
          int_size = string.to_i
          raise InvalidSampleSizeError.new(string) unless int_size.positive?
          int_size
        end
      end

      def to_double_class(double_suite)
        return nil unless double_suite

        case double_suite.downcase.strip
        when 'rspec'
          [
            '::RSpec::Mocks::Double',
            '::RSpec::Mocks::InstanceVerifyingDouble',
            '::RSpec::Mocks::ObjectVerifyingDouble',
            '::RSpec::Mocks::ClassVerifyingDouble',
          ]
        when 'minitest'
          ['::Minitest::Mock']
        else
          RBS.logger.warn "Unknown test suite - defaults to nil"
          nil
        end
      end
    end
  end
end
