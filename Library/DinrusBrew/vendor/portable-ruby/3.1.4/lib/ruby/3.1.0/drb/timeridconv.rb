# frozen_string_literal: false
require_relative 'drb'
require 'monitor'

module DRb

  # Timer id conversion keeps objects alive for a certain amount of time after
  # their last access.  The default time period is 600 seconds and can be
  # changed upon initialization.
  #
  # To use TimerIdConv:
  #
  #  DRb.install_id_conv TimerIdConv.new 60 # one minute

  class TimerIdConv < DRbIdConv
    class TimerHolder2 # :nodoc:
      include MonitorMixin

      class InvalidIndexError < RuntimeError; end

      def initialize(keeping=600)
        super()
        @sentinel = Object.new
        @gc = {}
        @renew = {}
        @keeping = keeping
        @expires = nil
      end

      def add(obj)
        synchronize do
          rotate
          key = obj.__id__
          @renew[key] = obj
          invoke_keeper
          return key
        end
      end

      def fetch(key)
        synchronize do
          rotate
          obj = peek(key)
          raise InvalidIndexError if obj == @sentinel
          @renew[key] = obj # KeepIt
          return obj
        end
      end

      private
      def peek(key)
        return @renew.fetch(key) { @gc.fetch(key, @sentinel) }
      end

      def invoke_keeper
        return if @expires
        @expires = Time.now + @keeping
        on_gc
      end

      def on_gc
        return unless Thread.main.alive?
        return if @expires.nil?
        Thread.new { rotate } if @expires < Time.now
        ObjectSpace.define_finalizer(Object.new) {on_gc}
      end

      def rotate
        synchronize do
          if @expires &.< Time.now
            @gc = @renew      # GCed
            @renew = {}
            @expires = @gc.empty? ? nil : Time.now + @keeping
          end
        end
      end
    end

    # Creates a new TimerIdConv which will hold objects for +keeping+ seconds.
    def initialize(keeping=600)
      @holder = TimerHolder2.new(keeping)
    end

    def to_obj(ref) # :nodoc:
      return super if ref.nil?
      @holder.fetch(ref)
    rescue TimerHolder2::InvalidIndexError
      raise "invalid reference"
    end

    def to_id(obj) # :nodoc:
      return @holder.add(obj)
    end
  end
end

# DRb.install_id_conv(TimerIdConv.new)
