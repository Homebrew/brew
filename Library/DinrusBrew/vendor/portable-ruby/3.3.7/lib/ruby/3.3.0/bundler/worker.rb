# frozen_string_literal: true

module Bundler
  class Worker
    POISON = Object.new

    class WrappedException < StandardError
      attr_reader :exception
      def initialize(exn)
        @exception = exn
      end
    end

    # @return [String] the name of the worker
    attr_reader :name

    # Creates a worker pool of specified size
    #
    # @param size [Integer] Size of pool
    # @param name [String] name the name of the worker
    # @param func [Proc] job to run in inside the worker pool
    def initialize(size, name, func)
      @name = name
      @request_queue = Thread::Queue.new
      @response_queue = Thread::Queue.new
      @func = func
      @size = size
      @threads = nil
      @previous_interrupt_handler = nil
    end

    # Enqueue a request to be executed in the worker pool
    #
    # @param obj [String] mostly it is name of spec that should be downloaded
    def enq(obj)
      create_threads unless @threads
      @request_queue.enq obj
    end

    # Retrieves results of job function being executed in worker pool
    def deq
      result = @response_queue.deq
      raise result.exception if result.is_a?(WrappedException)
      result
    end

    def stop
      stop_threads
    end

    private

    def process_queue(i)
      loop do
        obj = @request_queue.deq
        break if obj.equal? POISON
        @response_queue.enq apply_func(obj, i)
      end
    end

    def apply_func(obj, i)
      @func.call(obj, i)
    rescue Exception => e # rubocop:disable Lint/RescueException
      WrappedException.new(e)
    end

    # Stop the worker threads by sending a poison object down the request queue
    # so as worker threads after retrieving it, shut themselves down
    def stop_threads
      return unless @threads

      @threads.each { @request_queue.enq POISON }
      @threads.each(&:join)

      remove_interrupt_handler

      @threads = nil
    end

    def abort_threads
      Bundler.ui.debug("\n#{caller.join("\n")}")
      @threads.each(&:exit)
      exit 1
    end

    def create_threads
      creation_errors = []

      @threads = Array.new(@size) do |i|
        Thread.start { process_queue(i) }.tap do |thread|
          thread.name = "#{name} Worker ##{i}" if thread.respond_to?(:name=)
        end
      rescue ThreadError => e
        creation_errors << e
        nil
      end.compact

      add_interrupt_handler unless @threads.empty?

      return if creation_errors.empty?

      message = "Failed to create threads for the #{name} worker: #{creation_errors.map(&:to_s).uniq.join(", ")}"
      raise ThreadCreationError, message if @threads.empty?
      Bundler.ui.info message
    end

    def add_interrupt_handler
      @previous_interrupt_handler = trap("INT") { abort_threads }
    end

    def remove_interrupt_handler
      return unless @previous_interrupt_handler

      trap "INT", @previous_interrupt_handler
    end
  end
end
