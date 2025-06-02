# frozen_string_literal: false
require 'monitor'
require 'drb/drb'
require_relative 'rinda'
require 'forwardable'

module Rinda

  ##
  # A TupleEntry is a Tuple (i.e. a possible entry in some Tuplespace)
  # together with expiry and cancellation data.

  class TupleEntry

    include DRbUndumped

    attr_accessor :expires

    ##
    # Creates a TupleEntry based on +ary+ with an optional renewer or expiry
    # time +sec+.
    #
    # A renewer must implement the +renew+ method which returns a Numeric,
    # nil, or true to indicate when the tuple has expired.

    def initialize(ary, sec=nil)
      @cancel = false
      @expires = nil
      @tuple = make_tuple(ary)
      @renewer = nil
      renew(sec)
    end

    ##
    # Marks this TupleEntry as canceled.

    def cancel
      @cancel = true
    end

    ##
    # A TupleEntry is dead when it is canceled or expired.

    def alive?
      !canceled? && !expired?
    end

    ##
    # Return the object which makes up the tuple itself: the Array
    # or Hash.

    def value; @tuple.value; end

    ##
    # Returns the canceled status.

    def canceled?; @cancel; end

    ##
    # Has this tuple expired? (true/false).
    #
    # A tuple has expired when its expiry timer based on the +sec+ argument to
    # #initialize runs out.

    def expired?
      return true unless @expires
      return false if @expires > Time.now
      return true if @renewer.nil?
      renew(@renewer)
      return true unless @expires
      return @expires < Time.now
    end

    ##
    # Reset the expiry time according to +sec_or_renewer+.
    #
    # +nil+::    it is set to expire in the far future.
    # +true+::   it has expired.
    # Numeric::  it will expire in that many seconds.
    #
    # Otherwise the argument refers to some kind of renewer object
    # which will reset its expiry time.

    def renew(sec_or_renewer)
      sec, @renewer = get_renewer(sec_or_renewer)
      @expires = make_expires(sec)
    end

    ##
    # Returns an expiry Time based on +sec+ which can be one of:
    # Numeric:: +sec+ seconds into the future
    # +true+::  the expiry time is the start of 1970 (i.e. expired)
    # +nil+::   it is  Tue Jan 19 03:14:07 GMT Standard Time 2038 (i.e. when
    #           UNIX clocks will die)

    def make_expires(sec=nil)
      case sec
      when Numeric
        Time.now + sec
      when true
        Time.at(1)
      when nil
        Time.at(2**31-1)
      end
    end

    ##
    # Retrieves +key+ from the tuple.

    def [](key)
      @tuple[key]
    end

    ##
    # Fetches +key+ from the tuple.

    def fetch(key)
      @tuple.fetch(key)
    end

    ##
    # The size of the tuple.

    def size
      @tuple.size
    end

    ##
    # Creates a Rinda::Tuple for +ary+.

    def make_tuple(ary)
      Rinda::Tuple.new(ary)
    end

    private

    ##
    # Returns a valid argument to make_expires and the renewer or nil.
    #
    # Given +true+, +nil+, or Numeric, returns that value and +nil+ (no actual
    # renewer).  Otherwise it returns an expiry value from calling +it.renew+
    # and the renewer.

    def get_renewer(it)
      case it
      when Numeric, true, nil
        return it, nil
      else
        begin
          return it.renew, it
        rescue Exception
          return it, nil
        end
      end
    end

  end

  ##
  # A TemplateEntry is a Template together with expiry and cancellation data.

  class TemplateEntry < TupleEntry
    ##
    # Matches this TemplateEntry against +tuple+.  See Template#match for
    # details on how a Template matches a Tuple.

    def match(tuple)
      @tuple.match(tuple)
    end

    alias === match

    def make_tuple(ary) # :nodoc:
      Rinda::Template.new(ary)
    end

  end

  ##
  # <i>Documentation?</i>

  class WaitTemplateEntry < TemplateEntry

    attr_reader :found

    def initialize(place, ary, expires=nil)
      super(ary, expires)
      @place = place
      @cond = place.new_cond
      @found = nil
    end

    def cancel
      super
      signal
    end

    def wait
      @cond.wait
    end

    def read(tuple)
      @found = tuple
      signal
    end

    def signal
      @place.synchronize do
        @cond.signal
      end
    end

  end

  ##
  # A NotifyTemplateEntry is returned by TupleSpace#notify and is notified of
  # TupleSpace changes.  You may receive either your subscribed event or the
  # 'close' event when iterating over notifications.
  #
  # See TupleSpace#notify_event for valid notification types.
  #
  # == Example
  #
  #   ts = Rinda::TupleSpace.new
  #   observer = ts.notify 'write', [nil]
  #
  #   Thread.start do
  #     observer.each { |t| p t }
  #   end
  #
  #   3.times { |i| ts.write [i] }
  #
  # Outputs:
  #
  #   ['write', [0]]
  #   ['write', [1]]
  #   ['write', [2]]

  class NotifyTemplateEntry < TemplateEntry

    ##
    # Creates a new NotifyTemplateEntry that watches +place+ for +event+s that
    # match +tuple+.

    def initialize(place, event, tuple, expires=nil)
      ary = [event, Rinda::Template.new(tuple)]
      super(ary, expires)
      @queue = Thread::Queue.new
      @done = false
    end

    ##
    # Called by TupleSpace to notify this NotifyTemplateEntry of a new event.

    def notify(ev)
      @queue.push(ev)
    end

    ##
    # Retrieves a notification.  Raises RequestExpiredError when this
    # NotifyTemplateEntry expires.

    def pop
      raise RequestExpiredError if @done
      it = @queue.pop
      @done = true if it[0] == 'close'
      return it
    end

    ##
    # Yields event/tuple pairs until this NotifyTemplateEntry expires.

    def each # :yields: event, tuple
      while !@done
        it = pop
        yield(it)
      end
    rescue
    ensure
      cancel
    end

  end

  ##
  # TupleBag is an unordered collection of tuples. It is the basis
  # of Tuplespace.

  class TupleBag
    class TupleBin
      extend Forwardable
      def_delegators '@bin', :find_all, :delete_if, :each, :empty?

      def initialize
        @bin = []
      end

      def add(tuple)
        @bin.push(tuple)
      end

      def delete(tuple)
        idx = @bin.rindex(tuple)
        @bin.delete_at(idx) if idx
      end

      def find
        @bin.reverse_each do |x|
          return x if yield(x)
        end
        nil
      end
    end

    def initialize # :nodoc:
      @hash = {}
      @enum = enum_for(:each_entry)
    end

    ##
    # +true+ if the TupleBag to see if it has any expired entries.

    def has_expires?
      @enum.find do |tuple|
        tuple.expires
      end
    end

    ##
    # Add +tuple+ to the TupleBag.

    def push(tuple)
      key = bin_key(tuple)
      @hash[key] ||= TupleBin.new
      @hash[key].add(tuple)
    end

    ##
    # Removes +tuple+ from the TupleBag.

    def delete(tuple)
      key = bin_key(tuple)
      bin = @hash[key]
      return nil unless bin
      bin.delete(tuple)
      @hash.delete(key) if bin.empty?
      tuple
    end

    ##
    # Finds all live tuples that match +template+.
    def find_all(template)
      bin_for_find(template).find_all do |tuple|
        tuple.alive? && template.match(tuple)
      end
    end

    ##
    # Finds a live tuple that matches +template+.

    def find(template)
      bin_for_find(template).find do |tuple|
        tuple.alive? && template.match(tuple)
      end
    end

    ##
    # Finds all tuples in the TupleBag which when treated as templates, match
    # +tuple+ and are alive.

    def find_all_template(tuple)
      @enum.find_all do |template|
        template.alive? && template.match(tuple)
      end
    end

    ##
    # Delete tuples which dead tuples from the TupleBag, returning the deleted
    # tuples.

    def delete_unless_alive
      deleted = []
      @hash.each do |key, bin|
        bin.delete_if do |tuple|
          if tuple.alive?
            false
          else
            deleted.push(tuple)
            true
          end
        end
      end
      deleted
    end

    private
    def each_entry(&blk)
      @hash.each do |k, v|
        v.each(&blk)
      end
    end

    def bin_key(tuple)
      head = tuple[0]
      if head.class == Symbol
        return head
      else
        false
      end
    end

    def bin_for_find(template)
      key = bin_key(template)
      key ? @hash.fetch(key, []) : @enum
    end
  end

  ##
  # The Tuplespace manages access to the tuples it contains,
  # ensuring mutual exclusion requirements are met.
  #
  # The +sec+ option for the write, take, move, read and notify methods may
  # either be a number of seconds or a Renewer object.

  class TupleSpace

    include DRbUndumped
    include MonitorMixin

    ##
    # Creates a new TupleSpace.  +period+ is used to control how often to look
    # for dead tuples after modifications to the TupleSpace.
    #
    # If no dead tuples are found +period+ seconds after the last
    # modification, the TupleSpace will stop looking for dead tuples.

    def initialize(period=60)
      super()
      @bag = TupleBag.new
      @read_waiter = TupleBag.new
      @take_waiter = TupleBag.new
      @notify_waiter = TupleBag.new
      @period = period
      @keeper = nil
    end

    ##
    # Adds +tuple+

    def write(tuple, sec=nil)
      entry = create_entry(tuple, sec)
      synchronize do
        if entry.expired?
          @read_waiter.find_all_template(entry).each do |template|
            template.read(tuple)
          end
          notify_event('write', entry.value)
          notify_event('delete', entry.value)
        else
          @bag.push(entry)
          start_keeper if entry.expires
          @read_waiter.find_all_template(entry).each do |template|
            template.read(tuple)
          end
          @take_waiter.find_all_template(entry).each do |template|
            template.signal
          end
          notify_event('write', entry.value)
        end
      end
      entry
    end

    ##
    # Removes +tuple+

    def take(tuple, sec=nil, &block)
      move(nil, tuple, sec, &block)
    end

    ##
    # Moves +tuple+ to +port+.

    def move(port, tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, sec)
      yield(template) if block_given?
      synchronize do
        entry = @bag.find(template)
        if entry
          port.push(entry.value) if port
          @bag.delete(entry)
          notify_event('take', entry.value)
          return port ? nil : entry.value
        end
        raise RequestExpiredError if template.expired?

        begin
          @take_waiter.push(template)
          start_keeper if template.expires
          while true
            raise RequestCanceledError if template.canceled?
            raise RequestExpiredError if template.expired?
            entry = @bag.find(template)
            if entry
              port.push(entry.value) if port
              @bag.delete(entry)
              notify_event('take', entry.value)
              return port ? nil : entry.value
            end
            template.wait
          end
        ensure
          @take_waiter.delete(template)
        end
      end
    end

    ##
    # Reads +tuple+, but does not remove it.

    def read(tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, sec)
      yield(template) if block_given?
      synchronize do
        entry = @bag.find(template)
        return entry.value if entry
        raise RequestExpiredError if template.expired?

        begin
          @read_waiter.push(template)
          start_keeper if template.expires
          template.wait
          raise RequestCanceledError if template.canceled?
          raise RequestExpiredError if template.expired?
          return template.found
        ensure
          @read_waiter.delete(template)
        end
      end
    end

    ##
    # Returns all tuples matching +tuple+.  Does not remove the found tuples.

    def read_all(tuple)
      template = WaitTemplateEntry.new(self, tuple, nil)
      synchronize do
        entry = @bag.find_all(template)
        entry.collect do |e|
          e.value
        end
      end
    end

    ##
    # Registers for notifications of +event+.  Returns a NotifyTemplateEntry.
    # See NotifyTemplateEntry for examples of how to listen for notifications.
    #
    # +event+ can be:
    # 'write'::  A tuple was added
    # 'take'::   A tuple was taken or moved
    # 'delete':: A tuple was lost after being overwritten or expiring
    #
    # The TupleSpace will also notify you of the 'close' event when the
    # NotifyTemplateEntry has expired.

    def notify(event, tuple, sec=nil)
      template = NotifyTemplateEntry.new(self, event, tuple, sec)
      synchronize do
        @notify_waiter.push(template)
      end
      template
    end

    private

    def create_entry(tuple, sec)
      TupleEntry.new(tuple, sec)
    end

    ##
    # Removes dead tuples.

    def keep_clean
      synchronize do
        @read_waiter.delete_unless_alive.each do |e|
          e.signal
        end
        @take_waiter.delete_unless_alive.each do |e|
          e.signal
        end
        @notify_waiter.delete_unless_alive.each do |e|
          e.notify(['close'])
        end
        @bag.delete_unless_alive.each do |e|
          notify_event('delete', e.value)
        end
      end
    end

    ##
    # Notifies all registered listeners for +event+ of a status change of
    # +tuple+.

    def notify_event(event, tuple)
      ev = [event, tuple]
      @notify_waiter.find_all_template(ev).each do |template|
        template.notify(ev)
      end
    end

    ##
    # Creates a thread that scans the tuplespace for expired tuples.

    def start_keeper
      return if @keeper && @keeper.alive?
      @keeper = Thread.new do
        while true
          sleep(@period)
          synchronize do
            break unless need_keeper?
            keep_clean
          end
        end
      end
    end

    ##
    # Checks the tuplespace to see if it needs cleaning.

    def need_keeper?
      return true if @bag.has_expires?
      return true if @read_waiter.has_expires?
      return true if @take_waiter.has_expires?
      return true if @notify_waiter.has_expires?
    end

  end

end

