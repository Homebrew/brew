# frozen_string_literal: true
# date.rb: Written by Tadayoshi Funaba 1998-2011

require 'date_core'

class Date
  VERSION = '3.2.2' # :nodoc:

  def infinite?
    false
  end

  class Infinity < Numeric # :nodoc:

    def initialize(d=1) @d = d <=> 0 end

    def d() @d end

    protected :d

    def zero?() false end
    def finite?() false end
    def infinite?() d.nonzero? end
    def nan?() d.zero? end

    def abs() self.class.new end

    def -@() self.class.new(-d) end
    def +@() self.class.new(+d) end

    def <=>(other)
      case other
      when Infinity; return d <=> other.d
      when Float::INFINITY; return d <=> 1
      when -Float::INFINITY; return d <=> -1
      when Numeric; return d
      else
        begin
          l, r = other.coerce(self)
          return l <=> r
        rescue NoMethodError
        end
      end
      nil
    end

    def coerce(other)
      case other
      when Numeric; return -d, d
      else
        super
      end
    end

    def to_f
      return 0 if @d == 0
      if @d > 0
        Float::INFINITY
      else
        -Float::INFINITY
      end
    end

  end

end
