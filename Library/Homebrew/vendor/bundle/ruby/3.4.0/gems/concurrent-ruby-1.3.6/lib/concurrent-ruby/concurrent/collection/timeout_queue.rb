module Concurrent
  module Collection
    # @!visibility private
    # @!macro internal_implementation_note
    TimeoutQueueImplementation = if RUBY_VERSION >= '3.2'
                                   ::Queue
                                 else
                                   require 'concurrent/collection/ruby_timeout_queue'
                                   RubyTimeoutQueue
                                 end
    private_constant :TimeoutQueueImplementation

    # @!visibility private
    # @!macro timeout_queue
    class TimeoutQueue < TimeoutQueueImplementation
    end
  end
end
