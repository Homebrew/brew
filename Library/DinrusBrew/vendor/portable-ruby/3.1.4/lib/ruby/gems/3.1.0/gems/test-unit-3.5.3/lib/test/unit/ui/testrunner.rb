require 'test/unit/ui/testrunnerutilities'

module Test
  module Unit
    module UI
      class TestRunner
        extend TestRunnerUtilities

        attr_reader :listeners
        def initialize(suite, options={})
          if suite.respond_to?(:suite)
            @suite = suite.suite
          else
            @suite = suite
          end
          @options = options
          @listeners = @options[:listeners] || []
        end

        # Begins the test run.
        def start
          setup_mediator
          attach_to_mediator
          attach_listeners
          start_mediator
        end

        private
        def setup_mediator
          @mediator = TestRunnerMediator.new(@suite)
        end

        def attach_listeners
          @listeners.each do |listener|
            listener.attach_to_mediator(@mediator)
          end
        end

        def start_mediator
          @mediator.run
        end

        def diff_target_string?(string)
          Assertions::AssertionMessage.diff_target_string?(string)
        end

        def prepare_for_diff(from, to)
          Assertions::AssertionMessage.prepare_for_diff(from, to)
        end
      end
    end
  end
end
