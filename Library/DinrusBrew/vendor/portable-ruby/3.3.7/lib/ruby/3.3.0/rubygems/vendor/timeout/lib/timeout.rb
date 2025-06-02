# frozen_string_literal: true
# Timeout long-running blocks
#
# == Synopsis
#
#   require 'rubygems/vendor/timeout/lib/timeout'
#   status = Gem::Timeout::timeout(5) {
#     # Something that should be interrupted if it takes more than 5 seconds...
#   }
#
# == Description
#
# Gem::Timeout provides a way to auto-terminate a potentially long-running
# operation if it hasn't finished in a fixed amount of time.
#
# Previous versions didn't use a module for namespacing, however
# #timeout is provided for backwards compatibility.  You
# should prefer Gem::Timeout.timeout instead.
#
# == Copyright
#
# Copyright:: (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright:: (C) 2000  Information-technology Promotion Agency, Japan

module Gem::Timeout
  VERSION = "0.4.1"

  # Internal error raised to when a timeout is triggered.
  class ExitException < Exception
    def exception(*)
      self
    end
  end

  # Raised by Gem::Timeout.timeout when the block times out.
  class Error < RuntimeError
    def self.handle_timeout(message)
      exc = ExitException.new(message)

      begin
        yield exc
      rescue ExitException => e
        raise new(message) if exc.equal?(e)
        raise
      end
    end
  end

  # :stopdoc:
  CONDVAR = ConditionVariable.new
  QUEUE = Queue.new
  QUEUE_MUTEX = Mutex.new
  TIMEOUT_THREAD_MUTEX = Mutex.new
  @timeout_thread = nil
  private_constant :CONDVAR, :QUEUE, :QUEUE_MUTEX, :TIMEOUT_THREAD_MUTEX

  class Request
    attr_reader :deadline

    def initialize(thread, timeout, exception_class, message)
      @thread = thread
      @deadline = GET_TIME.call(Process::CLOCK_MONOTONIC) + timeout
      @exception_class = exception_class
      @message = message

      @mutex = Mutex.new
      @done = false # protected by @mutex
    end

    def done?
      @mutex.synchronize do
        @done
      end
    end

    def expired?(now)
      now >= @deadline
    end

    def interrupt
      @mutex.synchronize do
        unless @done
          @thread.raise @exception_class, @message
          @done = true
        end
      end
    end

    def finished
      @mutex.synchronize do
        @done = true
      end
    end
  end
  private_constant :Request

  def self.create_timeout_thread
    watcher = Thread.new do
      requests = []
      while true
        until QUEUE.empty? and !requests.empty? # wait to have at least one request
          req = QUEUE.pop
          requests << req unless req.done?
        end
        closest_deadline = requests.min_by(&:deadline).deadline

        now = 0.0
        QUEUE_MUTEX.synchronize do
          while (now = GET_TIME.call(Process::CLOCK_MONOTONIC)) < closest_deadline and QUEUE.empty?
            CONDVAR.wait(QUEUE_MUTEX, closest_deadline - now)
          end
        end

        requests.each do |req|
          req.interrupt if req.expired?(now)
        end
        requests.reject!(&:done?)
      end
    end
    ThreadGroup::Default.add(watcher) unless watcher.group.enclosed?
    watcher.name = "Gem::Timeout stdlib thread"
    watcher.thread_variable_set(:"\0__detached_thread__", true)
    watcher
  end
  private_class_method :create_timeout_thread

  def self.ensure_timeout_thread_created
    unless @timeout_thread and @timeout_thread.alive?
      TIMEOUT_THREAD_MUTEX.synchronize do
        unless @timeout_thread and @timeout_thread.alive?
          @timeout_thread = create_timeout_thread
        end
      end
    end
  end

  # We keep a private reference so that time mocking libraries won't break
  # Gem::Timeout.
  GET_TIME = Process.method(:clock_gettime)
  private_constant :GET_TIME

  # :startdoc:

  # Perform an operation in a block, raising an error if it takes longer than
  # +sec+ seconds to complete.
  #
  # +sec+:: Number of seconds to wait for the block to terminate. Any number
  #         may be used, including Floats to specify fractional seconds. A
  #         value of 0 or +nil+ will execute the block without any timeout.
  # +klass+:: Exception Class to raise if the block fails to terminate
  #           in +sec+ seconds.  Omitting will use the default, Gem::Timeout::Error
  # +message+:: Error message to raise with Exception Class.
  #             Omitting will use the default, "execution expired"
  #
  # Returns the result of the block *if* the block completed before
  # +sec+ seconds, otherwise throws an exception, based on the value of +klass+.
  #
  # The exception thrown to terminate the given block cannot be rescued inside
  # the block unless +klass+ is given explicitly. However, the block can use
  # ensure to prevent the handling of the exception.  For that reason, this
  # method cannot be relied on to enforce timeouts for untrusted blocks.
  #
  # If a scheduler is defined, it will be used to handle the timeout by invoking
  # Scheduler#timeout_after.
  #
  # Note that this is both a method of module Gem::Timeout, so you can <tt>include
  # Gem::Timeout</tt> into your classes so they have a #timeout method, as well as
  # a module method, so you can call it directly as Gem::Timeout.timeout().
  def timeout(sec, klass = nil, message = nil, &block)   #:yield: +sec+
    return yield(sec) if sec == nil or sec.zero?

    message ||= "execution expired"

    if Fiber.respond_to?(:current_scheduler) && (scheduler = Fiber.current_scheduler)&.respond_to?(:timeout_after)
      return scheduler.timeout_after(sec, klass || Error, message, &block)
    end

    Gem::Timeout.ensure_timeout_thread_created
    perform = Proc.new do |exc|
      request = Request.new(Thread.current, sec, exc, message)
      QUEUE_MUTEX.synchronize do
        QUEUE << request
        CONDVAR.signal
      end
      begin
        return yield(sec)
      ensure
        request.finished
      end
    end

    if klass
      perform.call(klass)
    else
      Error.handle_timeout(message, &perform)
    end
  end
  module_function :timeout
end
