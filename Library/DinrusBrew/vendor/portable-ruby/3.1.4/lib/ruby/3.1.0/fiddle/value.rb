# frozen_string_literal: true
require 'fiddle'

module Fiddle
  module ValueUtil #:nodoc: all
    def unsigned_value(val, ty)
      case ty.abs
      when TYPE_CHAR
        [val].pack("c").unpack("C")[0]
      when TYPE_SHORT
        [val].pack("s!").unpack("S!")[0]
      when TYPE_INT
        [val].pack("i!").unpack("I!")[0]
      when TYPE_LONG
        [val].pack("l!").unpack("L!")[0]
      else
        if defined?(TYPE_LONG_LONG) and
          ty.abs == TYPE_LONG_LONG
          [val].pack("q").unpack("Q")[0]
        else
          val
        end
      end
    end

    def signed_value(val, ty)
      case ty.abs
      when TYPE_CHAR
        [val].pack("C").unpack("c")[0]
      when TYPE_SHORT
        [val].pack("S!").unpack("s!")[0]
      when TYPE_INT
        [val].pack("I!").unpack("i!")[0]
      when TYPE_LONG
        [val].pack("L!").unpack("l!")[0]
      else
        if defined?(TYPE_LONG_LONG) and
          ty.abs == TYPE_LONG_LONG
          [val].pack("Q").unpack("q")[0]
        else
          val
        end
      end
    end

    def wrap_args(args, tys, funcs, &block)
      result = []
      tys ||= []
      args.each_with_index{|arg, idx|
        result.push(wrap_arg(arg, tys[idx], funcs, &block))
      }
      result
    end

    def wrap_arg(arg, ty, funcs = [], &block)
      funcs ||= []
      case arg
      when nil
        return 0
      when Pointer
        return arg.to_i
      when IO
        case ty
        when TYPE_VOIDP
          return Pointer[arg].to_i
        else
          return arg.to_i
        end
      when Function
        if( block )
          arg.bind_at_call(&block)
          funcs.push(arg)
        elsif !arg.bound?
          raise(RuntimeError, "block must be given.")
        end
        return arg.to_i
      when String
        if( ty.is_a?(Array) )
          return arg.unpack('C*')
        else
          case SIZEOF_VOIDP
          when SIZEOF_LONG
            return [arg].pack("p").unpack("l!")[0]
          else
            if defined?(SIZEOF_LONG_LONG) and
              SIZEOF_VOIDP == SIZEOF_LONG_LONG
              return [arg].pack("p").unpack("q")[0]
            else
              raise(RuntimeError, "sizeof(void*)?")
            end
          end
        end
      when Float, Integer
        return arg
      when Array
        if( ty.is_a?(Array) ) # used only by struct
          case ty[0]
          when TYPE_VOIDP
            return arg.collect{|v| Integer(v)}
          when TYPE_CHAR
            if( arg.is_a?(String) )
              return val.unpack('C*')
            end
          end
          return arg
        else
          return arg
        end
      else
        if( arg.respond_to?(:to_ptr) )
          return arg.to_ptr.to_i
        else
          begin
            return Integer(arg)
          rescue
            raise(ArgumentError, "unknown argument type: #{arg.class}")
          end
        end
      end
    end
  end
end
