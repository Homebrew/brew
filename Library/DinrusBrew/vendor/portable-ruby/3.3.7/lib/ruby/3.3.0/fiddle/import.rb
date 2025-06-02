# frozen_string_literal: true
require 'fiddle'
require 'fiddle/struct'
require 'fiddle/cparser'

module Fiddle

  # Used internally by Fiddle::Importer
  class CompositeHandler
    # Create a new handler with the open +handlers+
    #
    # Used internally by Fiddle::Importer.dlload
    def initialize(handlers)
      @handlers = handlers
    end

    # Array of the currently loaded libraries.
    def handlers()
      @handlers
    end

    # Returns the address as an Integer from any handlers with the function
    # named +symbol+.
    #
    # Raises a DLError if the handle is closed.
    def sym(symbol)
      @handlers.each{|handle|
        if( handle )
          begin
            addr = handle.sym(symbol)
            return addr
          rescue DLError
          end
        end
      }
      return nil
    end

    # See Fiddle::CompositeHandler.sym
    def [](symbol)
      sym(symbol)
    end
  end

  # A DSL that provides the means to dynamically load libraries and build
  # modules around them including calling extern functions within the C
  # library that has been loaded.
  #
  # == Example
  #
  #   require 'fiddle'
  #   require 'fiddle/import'
  #
  #   module LibSum
  #   	extend Fiddle::Importer
  #   	dlload './libsum.so'
  #   	extern 'double sum(double*, int)'
  #   	extern 'double split(double)'
  #   end
  #
  module Importer
    include Fiddle
    include CParser
    extend Importer

    attr_reader :type_alias
    private :type_alias

    # Creates an array of handlers for the given +libs+, can be an instance of
    # Fiddle::Handle, Fiddle::Importer, or will create a new instance of
    # Fiddle::Handle using Fiddle.dlopen
    #
    # Raises a DLError if the library cannot be loaded.
    #
    # See Fiddle.dlopen
    def dlload(*libs)
      handles = libs.collect{|lib|
        case lib
        when nil
          nil
        when Handle
          lib
        when Importer
          lib.handlers
        else
          Fiddle.dlopen(lib)
        end
      }.flatten()
      @handler = CompositeHandler.new(handles)
      @func_map = {}
      @type_alias = {}
    end

    # Sets the type alias for +alias_type+ as +orig_type+
    def typealias(alias_type, orig_type)
      @type_alias[alias_type] = orig_type
    end

    # Returns the sizeof +ty+, using Fiddle::Importer.parse_ctype to determine
    # the C type and the appropriate Fiddle constant.
    def sizeof(ty)
      case ty
      when String
        ty = parse_ctype(ty, type_alias).abs()
        case ty
        when TYPE_CHAR
          return SIZEOF_CHAR
        when TYPE_SHORT
          return SIZEOF_SHORT
        when TYPE_INT
          return SIZEOF_INT
        when TYPE_LONG
          return SIZEOF_LONG
        when TYPE_FLOAT
          return SIZEOF_FLOAT
        when TYPE_DOUBLE
          return SIZEOF_DOUBLE
        when TYPE_VOIDP
          return SIZEOF_VOIDP
        when TYPE_CONST_STRING
          return SIZEOF_CONST_STRING
        when TYPE_BOOL
          return SIZEOF_BOOL
        else
          if defined?(TYPE_LONG_LONG) and
            ty == TYPE_LONG_LONG
            return SIZEOF_LONG_LONG
          else
            raise(DLError, "unknown type: #{ty}")
          end
        end
      when Class
        if( ty.instance_methods().include?(:to_ptr) )
          return ty.size()
        end
      end
      return Pointer[ty].size()
    end

    def parse_bind_options(opts)
      h = {}
      while( opt = opts.shift() )
        case opt
        when :stdcall, :cdecl
          h[:call_type] = opt
        when :carried, :temp, :temporal, :bind
          h[:callback_type] = opt
          h[:carrier] = opts.shift()
        else
          h[opt] = true
        end
      end
      h
    end
    private :parse_bind_options

    # :stopdoc:
    CALL_TYPE_TO_ABI = Hash.new { |h, k|
      raise RuntimeError, "unsupported call type: #{k}"
    }.merge({ :stdcall => Function.const_defined?(:STDCALL) ? Function::STDCALL :
                          Function::DEFAULT,
              :cdecl   => Function::DEFAULT,
              nil      => Function::DEFAULT
            }).freeze
    private_constant :CALL_TYPE_TO_ABI
    # :startdoc:

    # Creates a global method from the given C +signature+.
    def extern(signature, *opts)
      symname, ctype, argtype = parse_signature(signature, type_alias)
      opt = parse_bind_options(opts)
      f = import_function(symname, ctype, argtype, opt[:call_type])
      name = symname.gsub(/@.+/,'')
      @func_map[name] = f
      # define_method(name){|*args,&block| f.call(*args,&block)}
      begin
        /^(.+?):(\d+)/ =~ caller.first
        file, line = $1, $2.to_i
      rescue
        file, line = __FILE__, __LINE__+3
      end
      module_eval(<<-EOS, file, line)
        def #{name}(*args, &block)
          @func_map['#{name}'].call(*args,&block)
        end
      EOS
      module_function(name)
      f
    end

    # Creates a global method from the given C +signature+ using the given
    # +opts+ as bind parameters with the given block.
    def bind(signature, *opts, &blk)
      name, ctype, argtype = parse_signature(signature, type_alias)
      h = parse_bind_options(opts)
      case h[:callback_type]
      when :bind, nil
        f = bind_function(name, ctype, argtype, h[:call_type], &blk)
      else
        raise(RuntimeError, "unknown callback type: #{h[:callback_type]}")
      end
      @func_map[name] = f
      #define_method(name){|*args,&block| f.call(*args,&block)}
      begin
        /^(.+?):(\d+)/ =~ caller.first
        file, line = $1, $2.to_i
      rescue
        file, line = __FILE__, __LINE__+3
      end
      module_eval(<<-EOS, file, line)
        def #{name}(*args,&block)
          @func_map['#{name}'].call(*args,&block)
        end
      EOS
      module_function(name)
      f
    end

    # Creates a class to wrap the C struct described by +signature+.
    #
    #   MyStruct = struct ['int i', 'char c']
    def struct(signature)
      tys, mems = parse_struct_signature(signature, type_alias)
      Fiddle::CStructBuilder.create(CStruct, tys, mems)
    end

    # Creates a class to wrap the C union described by +signature+.
    #
    #   MyUnion = union ['int i', 'char c']
    def union(signature)
      tys, mems = parse_struct_signature(signature, type_alias)
      Fiddle::CStructBuilder.create(CUnion, tys, mems)
    end

    # Returns the function mapped to +name+, that was created by either
    # Fiddle::Importer.extern or Fiddle::Importer.bind
    def [](name)
      @func_map[name]
    end

    # Creates a class to wrap the C struct with the value +ty+
    #
    # See also Fiddle::Importer.struct
    def create_value(ty, val=nil)
      s = struct([ty + " value"])
      ptr = s.malloc()
      if( val )
        ptr.value = val
      end
      return ptr
    end
    alias value create_value

    # Returns a new instance of the C struct with the value +ty+ at the +addr+
    # address.
    def import_value(ty, addr)
      s = struct([ty + " value"])
      ptr = s.new(addr)
      return ptr
    end


    # The Fiddle::CompositeHandler instance
    #
    # Will raise an error if no handlers are open.
    def handler
      (@handler ||= nil) or raise "call dlload before importing symbols and functions"
    end

    # Returns a new Fiddle::Pointer instance at the memory address of the given
    # +name+ symbol.
    #
    # Raises a DLError if the +name+ doesn't exist.
    #
    # See Fiddle::CompositeHandler.sym and Fiddle::Handle.sym
    def import_symbol(name)
      addr = handler.sym(name)
      if( !addr )
        raise(DLError, "cannot find the symbol: #{name}")
      end
      Pointer.new(addr)
    end

    # Returns a new Fiddle::Function instance at the memory address of the given
    # +name+ function.
    #
    # Raises a DLError if the +name+ doesn't exist.
    #
    # * +argtype+ is an Array of arguments, passed to the +name+ function.
    # * +ctype+ is the return type of the function
    # * +call_type+ is the ABI of the function
    #
    # See also Fiddle:Function.new
    #
    # See Fiddle::CompositeHandler.sym and Fiddle::Handler.sym
    def import_function(name, ctype, argtype, call_type = nil)
      addr = handler.sym(name)
      if( !addr )
        raise(DLError, "cannot find the function: #{name}()")
      end
      Function.new(addr, argtype, ctype, CALL_TYPE_TO_ABI[call_type],
                   name: name)
    end

    # Returns a new closure wrapper for the +name+ function.
    #
    # * +ctype+ is the return type of the function
    # * +argtype+ is an Array of arguments, passed to the callback function
    # * +call_type+ is the abi of the closure
    # * +block+ is passed to the callback
    #
    # See Fiddle::Closure
    def bind_function(name, ctype, argtype, call_type = nil, &block)
      abi = CALL_TYPE_TO_ABI[call_type]
      closure = Class.new(Fiddle::Closure) {
        define_method(:call, block)
      }.new(ctype, argtype, abi)

      Function.new(closure, argtype, ctype, abi, name: name)
    end
  end
end
