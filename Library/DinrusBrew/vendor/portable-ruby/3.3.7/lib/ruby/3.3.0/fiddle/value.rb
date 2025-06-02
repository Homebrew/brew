# frozen_string_literal: true
require 'fiddle'

module Fiddle
  module ValueUtil #:nodoc: all
    def unsigned_value(val, ty)
      case ty.abs
      when TYPE_CHAR
        [val].pack("c").unpack1("C")
      when TYPE_SHORT
        [val].pack("s!").unpack1("S!")
      when TYPE_INT
        [val].pack("i!").unpack1("I!")
      when TYPE_LONG
        [val].pack("l!").unpack1("L!")
      else
        if defined?(TYPE_LONG_LONG) and
          ty.abs == TYPE_LONG_LONG
          [val].pack("q").unpack1("Q")
        else
          val
        end
      end
    end

    def signed_value(val, ty)
      case ty.abs
      when TYPE_CHAR
        [val].pack("C").unpack1("c")
      when TYPE_SHORT
        [val].pack("S!").unpack1("s!")
      when TYPE_INT
        [val].pack("I!").unpack1("i!")
      when TYPE_LONG
        [val].pack("L!").unpack1("l!")
      else
        if defined?(TYPE_LONG_LONG) and
          ty.abs == TYPE_LONG_LONG
          [val].pack("Q").unpack1("q")
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
            return [arg].pack("p").unpack1("l!")
          else
            if defined?(SIZEOF_LONG_LONG) and
              SIZEOF_VOIDP == SIZEOF_LONG_LONG
              return [arg].pack("p").unpack1("q")
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
        end
        return arg
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
