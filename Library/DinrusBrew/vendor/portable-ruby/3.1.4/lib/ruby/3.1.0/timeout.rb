# frozen_string_literal: false
# Timeout long-running blocks
#
# == Synopsis
#
#   require 'timeout'
#   status = Timeout::timeout(5) {
#     # Something that should be interrupted if it takes more than 5 seconds...
#   }
#
# == Description
#
# Timeout provides a way to auto-terminate a potentially long-running
# operation if it hasn't finished in a fixed amount of time.
#
# Previous versions didn't use a module for namespacing, however
# #timeout is provided for backwards compatibility.  You
# should prefer Timeout.timeout instead.
#
# == Copyright
#
# Copyright:: (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright:: (C) 2000  Information-technology Promotion Agency, Japan

module Timeout
  VERSION = "0.2.0".freeze

  # Raised by Timeout.timeout when the block times out.
  class Error < RuntimeError
    attr_reader :thread

    def self.catch(*args)
      exc = new(*args)
      exc.instance_variable_set(:@thread, Thread.current)
      exc.instance_variable_set(:@catch_value, exc)
      ::Kernel.catch(exc) {yield exc}
    end

    def exception(*)
      # TODO: use Fiber.current to see if self can be thrown
      if self.thread == Thread.current
        bt = caller
        begin
          throw(@catch_value, bt)
        rescue UncaughtThrowError
        end
      end
      super
    end
  end

  # :stopdoc:
  THIS_FILE = /\A#{Regexp.quote(__FILE__)}:/o
  CALLER_OFFSET = ((c = caller[0]) && THIS_FILE =~ c) ? 1 : 0
  private_constant :THIS_FILE, :CALLER_OFFSET
  # :startdoc:

  # Perform an operation in a block, raising an error if it takes longer than
  # +sec+ seconds to complete.
  #
  # +sec+:: Number of seconds to wait for the block to terminate. Any number
  #         may be used, including Floats to specify fractional seconds. A
  #         value of 0 or +nil+ will execute the block without any timeout.
  # +klass+:: Exception Class to raise if the block fails to terminate
  #           in +sec+ seconds.  Omitting will use the default, Timeout::Error
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
  # Note that this is both a method of module Timeout, so you can <tt>include
  # Timeout</tt> into your classes so they have a #timeout method, as well as
  # a module method, so you can call it directly as Timeout.timeout().
  def timeout(sec, klass = nil, message = nil, &block)   #:yield: +sec+
    return yield(sec) if sec == nil or sec.zero?

    message ||= "execution expired".freeze

    if Fiber.respond_to?(:current_scheduler) && (scheduler = Fiber.current_scheduler)&.respond_to?(:timeout_after)
      return scheduler.timeout_after(sec, klass || Error, message, &block)
    end

    from = "from #{caller_locations(1, 1)[0]}" if $DEBUG
    e = Error
    bl = proc do |exception|
      begin
        x = Thread.current
        y = Thread.start {
          Thread.current.name = from
          begin
            sleep sec
          rescue => e
            x.raise e
          else
            x.raise exception, message
          end
        }
        return yield(sec)
      ensure
        if y
          y.kill
          y.join # make sure y is dead.
        end
      end
    end
    if klass
      begin
        bl.call(klass)
      rescue klass => e
        message = e.message
        bt = e.backtrace
      end
    else
      bt = Error.catch(message, &bl)
    end
    level = -caller(CALLER_OFFSET).size-2
    while THIS_FILE =~ bt[level]
      bt.delete_at(level)
    end
    raise(e, message, bt)
  end

  module_function :timeout
end
