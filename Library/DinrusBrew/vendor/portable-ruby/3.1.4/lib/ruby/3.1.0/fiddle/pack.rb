# frozen_string_literal: true
require 'fiddle'

module Fiddle
  module PackInfo # :nodoc: all
    ALIGN_MAP = {
      TYPE_VOIDP => ALIGN_VOIDP,
      TYPE_CHAR  => ALIGN_CHAR,
      TYPE_SHORT => ALIGN_SHORT,
      TYPE_INT   => ALIGN_INT,
      TYPE_LONG  => ALIGN_LONG,
      TYPE_FLOAT => ALIGN_FLOAT,
      TYPE_DOUBLE => ALIGN_DOUBLE,
      -TYPE_CHAR  => ALIGN_CHAR,
      -TYPE_SHORT => ALIGN_SHORT,
      -TYPE_INT   => ALIGN_INT,
      -TYPE_LONG  => ALIGN_LONG,
    }

    PACK_MAP = {
      TYPE_VOIDP => "l!",
      TYPE_CHAR  => "c",
      TYPE_SHORT => "s!",
      TYPE_INT   => "i!",
      TYPE_LONG  => "l!",
      TYPE_FLOAT => "f",
      TYPE_DOUBLE => "d",
      -TYPE_CHAR  => "c",
      -TYPE_SHORT => "s!",
      -TYPE_INT   => "i!",
      -TYPE_LONG  => "l!",
    }

    SIZE_MAP = {
      TYPE_VOIDP => SIZEOF_VOIDP,
      TYPE_CHAR  => SIZEOF_CHAR,
      TYPE_SHORT => SIZEOF_SHORT,
      TYPE_INT   => SIZEOF_INT,
      TYPE_LONG  => SIZEOF_LONG,
      TYPE_FLOAT => SIZEOF_FLOAT,
      TYPE_DOUBLE => SIZEOF_DOUBLE,
      -TYPE_CHAR  => SIZEOF_CHAR,
      -TYPE_SHORT => SIZEOF_SHORT,
      -TYPE_INT   => SIZEOF_INT,
      -TYPE_LONG  => SIZEOF_LONG,
    }
    if defined?(TYPE_LONG_LONG)
      ALIGN_MAP[TYPE_LONG_LONG] = ALIGN_MAP[-TYPE_LONG_LONG] = ALIGN_LONG_LONG
      PACK_MAP[TYPE_LONG_LONG] = PACK_MAP[-TYPE_LONG_LONG] = "q"
      SIZE_MAP[TYPE_LONG_LONG] = SIZE_MAP[-TYPE_LONG_LONG] = SIZEOF_LONG_LONG
      PACK_MAP[TYPE_VOIDP] = "q" if SIZEOF_LONG_LONG == SIZEOF_VOIDP
    end

    def align(addr, align)
      d = addr % align
      if( d == 0 )
        addr
      else
        addr + (align - d)
      end
    end
    module_function :align
  end

  class Packer # :nodoc: all
    include PackInfo

    def self.[](*types)
      new(types)
    end

    def initialize(types)
      parse_types(types)
    end

    def size()
      @size
    end

    def pack(ary)
      case SIZEOF_VOIDP
      when SIZEOF_LONG
        ary.pack(@template)
      else
        if defined?(TYPE_LONG_LONG) and
          SIZEOF_VOIDP == SIZEOF_LONG_LONG
          ary.pack(@template)
        else
          raise(RuntimeError, "sizeof(void*)?")
        end
      end
    end

    def unpack(ary)
      case SIZEOF_VOIDP
      when SIZEOF_LONG
        ary.join().unpack(@template)
      else
        if defined?(TYPE_LONG_LONG) and
          SIZEOF_VOIDP == SIZEOF_LONG_LONG
          ary.join().unpack(@template)
        else
          raise(RuntimeError, "sizeof(void*)?")
        end
      end
    end

    private

    def parse_types(types)
      @template = "".dup
      addr     = 0
      types.each{|t|
        orig_addr = addr
        if( t.is_a?(Array) )
          addr = align(orig_addr, ALIGN_MAP[TYPE_VOIDP])
        else
          addr = align(orig_addr, ALIGN_MAP[t])
        end
        d = addr - orig_addr
        if( d > 0 )
          @template << "x#{d}"
        end
        if( t.is_a?(Array) )
          @template << (PACK_MAP[t[0]] * t[1])
          addr += (SIZE_MAP[t[0]] * t[1])
        else
          @template << PACK_MAP[t]
          addr += SIZE_MAP[t]
        end
      }
      addr = align(addr, ALIGN_MAP[TYPE_VOIDP])
      @size = addr
    end
  end
end
