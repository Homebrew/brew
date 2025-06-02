#--
#
#
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# see the file "COPYING".
#
#++

module Racc

  # An "indexed" set.  All items must respond to :ident.
  class ISet

    def initialize(a = [])
      @set = a
    end

    attr_reader :set

    def add(i)
      @set[i.ident] = i
    end

    def [](key)
      @set[key.ident]
    end

    def []=(key, val)
      @set[key.ident] = val
    end

    alias include? []
    alias key? []

    def update(other)
      s = @set
      o = other.set
      o.each_index do |idx|
        if t = o[idx]
          s[idx] = t
        end
      end
    end

    def update_a(a)
      s = @set
      a.each {|i| s[i.ident] = i }
    end

    def delete(key)
      i = @set[key.ident]
      @set[key.ident] = nil
      i
    end

    def each(&block)
      @set.compact.each(&block)
    end

    def to_a
      @set.compact
    end

    def to_s
      "[#{@set.compact.join(' ')}]"
    end

    alias inspect to_s

    def size
      @set.nitems
    end

    def empty?
      @set.nitems == 0
    end

    def clear
      @set.clear
    end

    def dup
      ISet.new(@set.dup)
    end

  end   # class ISet

end   # module Racc
