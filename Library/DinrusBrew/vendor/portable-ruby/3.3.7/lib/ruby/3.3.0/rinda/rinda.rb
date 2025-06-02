# frozen_string_literal: false
require 'drb/drb'

##
# A module to implement the Linda distributed computing paradigm in Ruby.
#
# Rinda is part of DRb (dRuby).
#
# == Example(s)
#
# See the sample/drb/ directory in the Ruby distribution, from 1.8.2 onwards.
#
#--
# TODO
# == Introduction to Linda/rinda?
#
# == Why is this library separate from DRb?

module Rinda

  VERSION = "0.2.0"

  ##
  # Rinda error base class

  class RindaError < RuntimeError; end

  ##
  # Raised when a hash-based tuple has an invalid key.

  class InvalidHashTupleKey < RindaError; end

  ##
  # Raised when trying to use a canceled tuple.

  class RequestCanceledError < ThreadError; end

  ##
  # Raised when trying to use an expired tuple.

  class RequestExpiredError < ThreadError; end

  ##
  # A tuple is the elementary object in Rinda programming.
  # Tuples may be matched against templates if the tuple and
  # the template are the same size.

  class Tuple

    ##
    # Creates a new Tuple from +ary_or_hash+ which must be an Array or Hash.

    def initialize(ary_or_hash)
      if hash?(ary_or_hash)
        init_with_hash(ary_or_hash)
      else
        init_with_ary(ary_or_hash)
      end
    end

    ##
    # The number of elements in the tuple.

    def size
      @tuple.size
    end

    ##
    # Accessor method for elements of the tuple.

    def [](k)
      @tuple[k]
    end

    ##
    # Fetches item +k+ from the tuple.

    def fetch(k)
      @tuple.fetch(k)
    end

    ##
    # Iterate through the tuple, yielding the index or key, and the
    # value, thus ensuring arrays are iterated similarly to hashes.

    def each # FIXME
      if Hash === @tuple
        @tuple.each { |k, v| yield(k, v) }
      else
        @tuple.each_with_index { |v, k| yield(k, v) }
      end
    end

    ##
    # Return the tuple itself
    def value
      @tuple
    end

    private

    def hash?(ary_or_hash)
      ary_or_hash.respond_to?(:keys)
    end

    ##
    # Munges +ary+ into a valid Tuple.

    def init_with_ary(ary)
      @tuple = Array.new(ary.size)
      @tuple.size.times do |i|
        @tuple[i] = ary[i]
      end
    end

    ##
    # Ensures +hash+ is a valid Tuple.

    def init_with_hash(hash)
      @tuple = Hash.new
      hash.each do |k, v|
        raise InvalidHashTupleKey unless String === k
        @tuple[k] = v
      end
    end

  end

  ##
  # Templates are used to match tuples in Rinda.

  class Template < Tuple

    ##
    # Matches this template against +tuple+.  The +tuple+ must be the same
    # size as the template.  An element with a +nil+ value in a template acts
    # as a wildcard, matching any value in the corresponding position in the
    # tuple.  Elements of the template match the +tuple+ if the are #== or
    # #===.
    #
    #   Template.new([:foo, 5]).match   Tuple.new([:foo, 5]) # => true
    #   Template.new([:foo, nil]).match Tuple.new([:foo, 5]) # => true
    #   Template.new([String]).match    Tuple.new(['hello']) # => true
    #
    #   Template.new([:foo]).match      Tuple.new([:foo, 5]) # => false
    #   Template.new([:foo, 6]).match   Tuple.new([:foo, 5]) # => false
    #   Template.new([:foo, nil]).match Tuple.new([:foo])    # => false
    #   Template.new([:foo, 6]).match   Tuple.new([:foo])    # => false

    def match(tuple)
      return false unless tuple.respond_to?(:size)
      return false unless tuple.respond_to?(:fetch)
      return false unless self.size == tuple.size
      each do |k, v|
        begin
          it = tuple.fetch(k)
        rescue
          return false
        end
        next if v.nil?
        next if v == it
        next if v === it
        return false
      end
      return true
    end

    ##
    # Alias for #match.

    def ===(tuple)
      match(tuple)
    end

  end

  ##
  # <i>Documentation?</i>

  class DRbObjectTemplate

    ##
    # Creates a new DRbObjectTemplate that will match against +uri+ and +ref+.

    def initialize(uri=nil, ref=nil)
      @drb_uri = uri
      @drb_ref = ref
    end

    ##
    # This DRbObjectTemplate matches +ro+ if the remote object's drburi and
    # drbref are the same.  +nil+ is used as a wildcard.

    def ===(ro)
      return true if super(ro)
      unless @drb_uri.nil?
        return false unless (@drb_uri === ro.__drburi rescue false)
      end
      unless @drb_ref.nil?
        return false unless (@drb_ref === ro.__drbref rescue false)
      end
      true
    end

  end

  ##
  # TupleSpaceProxy allows a remote Tuplespace to appear as local.

  class TupleSpaceProxy
    ##
    # A Port ensures that a moved tuple arrives properly at its destination
    # and does not get lost.
    #
    # See https://bugs.ruby-lang.org/issues/8125

    class Port # :nodoc:
      attr_reader :value

      def self.deliver
        port = new

        begin
          yield(port)
        ensure
          port.close
        end

        port.value
      end

      def initialize
        @open = true
        @value = nil
      end

      ##
      # Don't let the DRb thread push to it when remote sends tuple

      def close
        @open = false
      end

      ##
      # Stores +value+ and ensure it does not get marshaled multiple times.

      def push value
        raise 'port closed' unless @open

        @value = value

        nil # avoid Marshal
      end
    end

    ##
    # Creates a new TupleSpaceProxy to wrap +ts+.

    def initialize(ts)
      @ts = ts
    end

    ##
    # Adds +tuple+ to the proxied TupleSpace.  See TupleSpace#write.

    def write(tuple, sec=nil)
      @ts.write(tuple, sec)
    end

    ##
    # Takes +tuple+ from the proxied TupleSpace.  See TupleSpace#take.

    def take(tuple, sec=nil, &block)
      Port.deliver do |port|
        @ts.move(DRbObject.new(port), tuple, sec, &block)
      end
    end

    ##
    # Reads +tuple+ from the proxied TupleSpace.  See TupleSpace#read.

    def read(tuple, sec=nil, &block)
      @ts.read(tuple, sec, &block)
    end

    ##
    # Reads all tuples matching +tuple+ from the proxied TupleSpace.  See
    # TupleSpace#read_all.

    def read_all(tuple)
      @ts.read_all(tuple)
    end

    ##
    # Registers for notifications of event +ev+ on the proxied TupleSpace.
    # See TupleSpace#notify

    def notify(ev, tuple, sec=nil)
      @ts.notify(ev, tuple, sec)
    end

  end

  ##
  # An SimpleRenewer allows a TupleSpace to check if a TupleEntry is still
  # alive.

  class SimpleRenewer

    include DRbUndumped

    ##
    # Creates a new SimpleRenewer that keeps an object alive for another +sec+
    # seconds.

    def initialize(sec=180)
      @sec = sec
    end

    ##
    # Called by the TupleSpace to check if the object is still alive.

    def renew
      @sec
    end
  end

end

