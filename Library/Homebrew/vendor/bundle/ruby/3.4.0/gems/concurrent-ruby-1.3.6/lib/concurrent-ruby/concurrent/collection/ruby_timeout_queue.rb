module Concurrent
  module Collection
    # @!visibility private
    # @!macro ruby_timeout_queue
    class RubyTimeoutQueue < ::Queue
      def initialize(*args)
        if RUBY_VERSION >= '3.2'
          raise "#{self.class.name} is not needed on Ruby 3.2 or later, use ::Queue instead"
        end

        super(*args)

        @mutex = Mutex.new
        @cond_var = ConditionVariable.new
      end

      def push(obj)
        @mutex.synchronize do
          super(obj)
          @cond_var.signal
        end
      end
      alias_method :enq, :push
      alias_method :<<, :push

      def pop(non_block = false, timeout: nil)
        if non_block && timeout
          raise ArgumentError, "can't set a timeout if non_block is enabled"
        end

        if non_block
          super(true)
        elsif timeout
          @mutex.synchronize do
            deadline = Concurrent.monotonic_time + timeout
            while (now = Concurrent.monotonic_time) < deadline && empty?
              @cond_var.wait(@mutex, deadline - now)
            end
            begin
              return super(true)
            rescue ThreadError
              # still empty
              nil
            end
          end
        else
          super(false)
        end
      end
      alias_method :deq, :pop
      alias_method :shift, :pop
    end
    private_constant :RubyTimeoutQueue
  end
end
