# frozen_string_literal: false
# = monitor.rb
#
# Copyright (C) 2001  Shugo Maeda <shugo@ruby-lang.org>
#
# This library is distributed under the terms of the Ruby license.
# You can freely distribute/modify this library.
#

require 'monitor.so'

#
# In concurrent programming, a monitor is an object or module intended to be
# used safely by more than one thread. The defining characteristic of a
# monitor is that its methods are executed with mutual exclusion. That is, at
# each point in time, at most one thread may be executing any of its methods.
# This mutual exclusion greatly simplifies reasoning about the implementation
# of monitors compared to reasoning about parallel code that updates a data
# structure.
#
# You can read more about the general principles on the Wikipedia page for
# Monitors[https://en.wikipedia.org/wiki/Monitor_%28synchronization%29].
#
# == Examples
#
# === Simple object.extend
#
#   require 'monitor.rb'
#
#   buf = []
#   buf.extend(MonitorMixin)
#   empty_cond = buf.new_cond
#
#   # consumer
#   Thread.start do
#     loop do
#       buf.synchronize do
#         empty_cond.wait_while { buf.empty? }
#         print buf.shift
#       end
#     end
#   end
#
#   # producer
#   while line = ARGF.gets
#     buf.synchronize do
#       buf.push(line)
#       empty_cond.signal
#     end
#   end
#
# The consumer thread waits for the producer thread to push a line to buf
# while <tt>buf.empty?</tt>. The producer thread (main thread) reads a
# line from ARGF and pushes it into buf then calls <tt>empty_cond.signal</tt>
# to notify the consumer thread of new data.
#
# === Simple Class include
#
#   require 'monitor'
#
#   class SynchronizedArray < Array
#
#     include MonitorMixin
#
#     def initialize(*args)
#       super(*args)
#     end
#
#     alias :old_shift :shift
#     alias :old_unshift :unshift
#
#     def shift(n=1)
#       self.synchronize do
#         self.old_shift(n)
#       end
#     end
#
#     def unshift(item)
#       self.synchronize do
#         self.old_unshift(item)
#       end
#     end
#
#     # other methods ...
#   end
#
# +SynchronizedArray+ implements an Array with synchronized access to items.
# This Class is implemented as subclass of Array which includes the
# MonitorMixin module.
#
module MonitorMixin
  #
  # FIXME: This isn't documented in Nutshell.
  #
  # Since MonitorMixin.new_cond returns a ConditionVariable, and the example
  # above calls while_wait and signal, this class should be documented.
  #
  class ConditionVariable
    #
    # Releases the lock held in the associated monitor and waits; reacquires the lock on wakeup.
    #
    # If +timeout+ is given, this method returns after +timeout+ seconds passed,
    # even if no other thread doesn't signal.
    #
    def wait(timeout = nil)
      @monitor.mon_check_owner
      @monitor.wait_for_cond(@cond, timeout)
    end

    #
    # Calls wait repeatedly while the given block yields a truthy value.
    #
    def wait_while
      while yield
        wait
      end
    end

    #
    # Calls wait repeatedly until the given block yields a truthy value.
    #
    def wait_until
      until yield
        wait
      end
    end

    #
    # Wakes up the first thread in line waiting for this lock.
    #
    def signal
      @monitor.mon_check_owner
      @cond.signal
    end

    #
    # Wakes up all threads waiting for this lock.
    #
    def broadcast
      @monitor.mon_check_owner
      @cond.broadcast
    end

    private

    def initialize(monitor)
      @monitor = monitor
      @cond = Thread::ConditionVariable.new
    end
  end

  def self.extend_object(obj)
    super(obj)
    obj.__send__(:mon_initialize)
  end

  #
  # Attempts to enter exclusive section.  Returns +false+ if lock fails.
  #
  def mon_try_enter
    @mon_data.try_enter
  end
  # For backward compatibility
  alias try_mon_enter mon_try_enter

  #
  # Enters exclusive section.
  #
  def mon_enter
    @mon_data.enter
  end

  #
  # Leaves exclusive section.
  #
  def mon_exit
    mon_check_owner
    @mon_data.exit
  end

  #
  # Returns true if this monitor is locked by any thread
  #
  def mon_locked?
    @mon_data.mon_locked?
  end

  #
  # Returns true if this monitor is locked by current thread.
  #
  def mon_owned?
    @mon_data.mon_owned?
  end

  #
  # Enters exclusive section and executes the block.  Leaves the exclusive
  # section automatically when the block exits.  See example under
  # +MonitorMixin+.
  #
  def mon_synchronize(&b)
    @mon_data.synchronize(&b)
  end
  alias synchronize mon_synchronize

  #
  # Creates a new MonitorMixin::ConditionVariable associated with the
  # Monitor object.
  #
  def new_cond
    unless defined?(@mon_data)
      mon_initialize
      @mon_initialized_by_new_cond = true
    end
    return ConditionVariable.new(@mon_data)
  end

  private

  # Use <tt>extend MonitorMixin</tt> or <tt>include MonitorMixin</tt> instead
  # of this constructor.  Have look at the examples above to understand how to
  # use this module.
  def initialize(...)
    super
    mon_initialize
  end

  # Initializes the MonitorMixin after being included in a class or when an
  # object has been extended with the MonitorMixin
  def mon_initialize
    if defined?(@mon_data)
      if defined?(@mon_initialized_by_new_cond)
        return # already initialized.
      elsif @mon_data_owner_object_id == self.object_id
        raise ThreadError, "already initialized"
      end
    end
    @mon_data = ::Monitor.new
    @mon_data_owner_object_id = self.object_id
  end

  def mon_check_owner
    @mon_data.mon_check_owner
  end
end

# Use the Monitor class when you want to have a lock object for blocks with
# mutual exclusion.
#
#   require 'monitor'
#
#   lock = Monitor.new
#   lock.synchronize do
#     # exclusive access
#   end
#
class Monitor
  def new_cond
    ::MonitorMixin::ConditionVariable.new(self)
  end

  # for compatibility
  alias try_mon_enter try_enter
  alias mon_try_enter try_enter
  alias mon_enter enter
  alias mon_exit exit
  alias mon_synchronize synchronize
end

# Documentation comments:
#  - All documentation comes from Nutshell.
#  - MonitorMixin.new_cond appears in the example, but is not documented in
#    Nutshell.
#  - All the internals (internal modules Accessible and Initializable, class
#    ConditionVariable) appear in RDoc.  It might be good to hide them, by
#    making them private, or marking them :nodoc:, etc.
#  - RDoc doesn't recognise aliases, so we have mon_synchronize documented, but
#    not synchronize.
#  - mon_owner is in Nutshell, but appears as an accessor in a separate module
#    here, so is hard/impossible to RDoc.  Some other useful accessors
#    (mon_count and some queue stuff) are also in this module, and don't appear
#    directly in the RDoc output.
#  - in short, it may be worth changing the code layout in this file to make the
#    documentation easier
