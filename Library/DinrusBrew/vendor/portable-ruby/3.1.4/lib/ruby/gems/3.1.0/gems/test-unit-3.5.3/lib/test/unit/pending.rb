require 'test/unit/util/backtracefilter'

module Test
  module Unit
    class Pending
      include Util::BacktraceFilter
      attr_reader :test_name, :location, :message
      attr_reader :method_name

      SINGLE_CHARACTER = 'P'
      LABEL = "Pending"

      # Creates a new Pending with the given location and
      # message.
      def initialize(test_name, location, message, options={})
        @test_name = test_name
        @location = location
        @message = message
        @method_name = options[:method_name]
      end

      # Returns a single character representation of a pending.
      def single_character_display
        SINGLE_CHARACTER
      end

      def label
        LABEL
      end

      # Returns a brief version of the error description.
      def short_display
        "#{@test_name}: #{@message.split("\n")[0]}"
      end

      # Returns a verbose version of the error description.
      def long_display
        backtrace = filter_backtrace(location).join("\n")
        "#{label}: #{@message}\n#{@test_name}\n#{backtrace}"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end

      def critical?
        true
      end
    end

    class PendedError < StandardError
    end


    module TestCasePendingSupport
      class << self
        def included(base)
          base.class_eval do
            include PendingHandler
          end
        end
      end

      # Marks the test or part of the test is pending.
      #
      # Example:
      #
      #     def test_pending
      #       pend
      #       # Not reached here
      #     end
      #
      #     def test_pending_with_here
      #       pend do
      #         # Ran here
      #         # Fails if the block doesn't raise any error.
      #         # Because it means the block is passed unexpectedly.
      #       end
      #       # Reached here
      #     end
      def pend(message=nil, &block)
        message ||= "pended."
        if block_given?
          pending = nil
          begin
            yield
          rescue Exception
            pending = Pending.new(name, filter_backtrace(caller), message,
                                  :method_name => @method_name)
            add_pending(pending)
          end
          unless pending
            flunk("Pending block should not be passed: #{message}")
          end
        else
          raise PendedError.new(message)
        end
      end

      private
      def add_pending(pending)
        problem_occurred
        current_result.add_pending(pending)
      end
    end

    module PendingHandler
      class << self
        def included(base)
          base.exception_handler(:handle_pended_error)
        end
      end

      private
      def handle_pended_error(exception)
        return false unless exception.is_a?(PendedError)
        pending = Pending.new(name,
                              filter_backtrace(exception.backtrace),
                              exception.message,
                              :method_name => @method_name)
        add_pending(pending)
        true
      end
    end

    module TestResultPendingSupport
      attr_reader :pendings

      # Records a Test::Unit::Pending.
      def add_pending(pending)
        @pendings << pending
        notify_fault(pending)
        notify_changed
      end

      # Returns the number of pendings this TestResult has
      # recorded.
      def pending_count
        @pendings.size
      end

      private
      def initialize_containers
        super
        @pendings = []
        @summary_generators << :pending_summary
      end

      def pending_summary
        "#{pending_count} pendings"
      end
    end
  end
end
