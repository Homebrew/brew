# frozen_string_literal: true
module Fiddle
  # A mixin that provides methods for parsing C struct and prototype signatures.
  #
  # == Example
  #   require 'fiddle/import'
  #
  #   include Fiddle::CParser
  #     #=> Object
  #
  #   parse_ctype('int')
  #     #=> Fiddle::TYPE_INT
  #
  #   parse_struct_signature(['int i', 'char c'])
  #     #=> [[Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], ["i", "c"]]
  #
  #   parse_signature('double sum(double, double)')
  #     #=> ["sum", Fiddle::TYPE_DOUBLE, [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE]]
  #
  module CParser
    # Parses a C struct's members
    #
    # Example:
    #   require 'fiddle/import'
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_struct_signature(['int i', 'char c'])
    #     #=> [[Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], ["i", "c"]]
    #
    #   parse_struct_signature(['char buffer[80]'])
    #     #=> [[[Fiddle::TYPE_CHAR, 80]], ["buffer"]]
    #
    def parse_struct_signature(signature, tymap=nil)
      if signature.is_a?(String)
        signature = split_arguments(signature, /[,;]/)
      elsif signature.is_a?(Hash)
        signature = [signature]
      end
      mems = []
      tys  = []
      signature.each{|msig|
        msig = compact(msig) if msig.is_a?(String)
        case msig
        when Hash
          msig.each do |struct_name, struct_signature|
            struct_name = struct_name.to_s if struct_name.is_a?(Symbol)
            struct_name = compact(struct_name)
            struct_count = nil
            if struct_name =~ /^([\w\*\s]+)\[(\d+)\]$/
              struct_count = $2.to_i
              struct_name = $1
            end
            if struct_signature.respond_to?(:entity_class)
              struct_type = struct_signature
            else
              parsed_struct = parse_struct_signature(struct_signature, tymap)
              struct_type = CStructBuilder.create(CStruct, *parsed_struct)
            end
            if struct_count
              ty = [struct_type, struct_count]
            else
              ty = struct_type
            end
            mems.push([struct_name, struct_type.members])
            tys.push(ty)
          end
        when /^[\w\*\s]+[\*\s](\w+)$/
          mems.push($1)
          tys.push(parse_ctype(msig, tymap))
        when /^[\w\*\s]+\(\*(\w+)\)\(.*?\)$/
          mems.push($1)
          tys.push(parse_ctype(msig, tymap))
        when /^([\w\*\s]+[\*\s])(\w+)\[(\d+)\]$/
          mems.push($2)
          tys.push([parse_ctype($1.strip, tymap), $3.to_i])
        when /^([\w\*\s]+)\[(\d+)\](\w+)$/
          mems.push($3)
          tys.push([parse_ctype($1.strip, tymap), $2.to_i])
        else
          raise(RuntimeError,"can't parse the struct member: #{msig}")
        end
      }
      return tys, mems
    end

    # Parses a C prototype signature
    #
    # If Hash +tymap+ is provided, the return value and the arguments from the
    # +signature+ are expected to be keys, and the value will be the C type to
    # be looked up.
    #
    # Example:
    #   require 'fiddle/import'
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_signature('double sum(double, double)')
    #     #=> ["sum", Fiddle::TYPE_DOUBLE, [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE]]
    #
    #   parse_signature('void update(void (*cb)(int code))')
    #     #=> ["update", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP]]
    #
    #   parse_signature('char (*getbuffer(void))[80]')
    #     #=> ["getbuffer", Fiddle::TYPE_VOIDP, []]
    #
    def parse_signature(signature, tymap=nil)
      tymap ||= {}
      case compact(signature)
      when /^(?:[\w\*\s]+)\(\*(\w+)\((.*?)\)\)(?:\[\w*\]|\(.*?\));?$/
        func, args = $1, $2
        return [func, TYPE_VOIDP, split_arguments(args).collect {|arg| parse_ctype(arg, tymap)}]
      when /^([\w\*\s]+[\*\s])(\w+)\((.*?)\);?$/
        ret, func, args = $1.strip, $2, $3
        return [func, parse_ctype(ret, tymap), split_arguments(args).collect {|arg| parse_ctype(arg, tymap)}]
      else
        raise(RuntimeError,"can't parse the function prototype: #{signature}")
      end
    end

    # Given a String of C type +ty+, returns the corresponding Fiddle constant.
    #
    # +ty+ can also accept an Array of C type Strings, and will be returned in
    # a corresponding Array.
    #
    # If Hash +tymap+ is provided, +ty+ is expected to be the key, and the
    # value will be the C type to be looked up.
    #
    # Example:
    #   require 'fiddle/import'
    #
    #   include Fiddle::CParser
    #     #=> Object
    #
    #   parse_ctype('int')
    #     #=> Fiddle::TYPE_INT
    #
    #   parse_ctype('double diff')
    #     #=> Fiddle::TYPE_DOUBLE
    #
    #   parse_ctype('unsigned char byte')
    #     #=> -Fiddle::TYPE_CHAR
    #
    #   parse_ctype('const char* const argv[]')
    #     #=> -Fiddle::TYPE_VOIDP
    #
    def parse_ctype(ty, tymap=nil)
      tymap ||= {}
      if ty.is_a?(Array)
        return [parse_ctype(ty[0], tymap), ty[1]]
      end
      ty = ty.gsub(/\Aconst\s+/, "")
      case ty
      when 'void'
        return TYPE_VOID
      when /\A(?:(?:signed\s+)?long\s+long(?:\s+int\s+)?|int64_t)(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_LONG_LONG)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_LONG_LONG
      when /\A(?:unsigned\s+long\s+long(?:\s+int\s+)?|uint64_t)(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_LONG_LONG)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_ULONG_LONG
      when /\Aunsigned\s+long(?:\s+int\s+)?(?:\s+\w+)?\z/,
           /\Aunsigned\s+int\s+long(?:\s+\w+)?\z/,
           /\Along(?:\s+int)?\s+unsigned(?:\s+\w+)?\z/,
           /\Aint\s+unsigned\s+long(?:\s+\w+)?\z/,
           /\A(?:int\s+)?long\s+unsigned(?:\s+\w+)?\z/
        return TYPE_ULONG
      when /\A(?:signed\s+)?long(?:\s+int\s+)?(?:\s+\w+)?\z/,
           /\A(?:signed\s+)?int\s+long(?:\s+\w+)?\z/,
           /\Along(?:\s+int)?\s+signed(?:\s+\w+)?\z/
        return TYPE_LONG
      when /\Aunsigned\s+short(?:\s+int\s+)?(?:\s+\w+)?\z/,
           /\Aunsigned\s+int\s+short(?:\s+\w+)?\z/,
           /\Ashort(?:\s+int)?\s+unsigned(?:\s+\w+)?\z/,
           /\Aint\s+unsigned\s+short(?:\s+\w+)?\z/,
           /\A(?:int\s+)?short\s+unsigned(?:\s+\w+)?\z/
        return TYPE_USHORT
      when /\A(?:signed\s+)?short(?:\s+int\s+)?(?:\s+\w+)?\z/,
           /\A(?:signed\s+)?int\s+short(?:\s+\w+)?\z/,
           /\Aint\s+(?:signed\s+)?short(?:\s+\w+)?\z/
        return TYPE_SHORT
      when /\A(?:signed\s+)?int(?:\s+\w+)?\z/
        return TYPE_INT
      when /\A(?:unsigned\s+int|uint)(?:\s+\w+)?\z/
        return TYPE_UINT
      when /\A(?:signed\s+)?char(?:\s+\w+)?\z/
        return TYPE_CHAR
      when /\Aunsigned\s+char(?:\s+\w+)?\z/
        return  TYPE_UCHAR
      when /\Aint8_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT8_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_INT8_T
      when /\Auint8_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT8_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_UINT8_T
      when /\Aint16_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT16_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_INT16_T
      when /\Auint16_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT16_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_UINT16_T
      when /\Aint32_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT32_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_INT32_T
      when /\Auint32_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT32_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_UINT32_T
      when /\Aint64_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT64_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_INT64_T
      when /\Auint64_t(?:\s+\w+)?\z/
        unless Fiddle.const_defined?(:TYPE_INT64_T)
          raise(RuntimeError, "unsupported type: #{ty}")
        end
        return TYPE_UINT64_T
      when /\Afloat(?:\s+\w+)?\z/
        return TYPE_FLOAT
      when /\Adouble(?:\s+\w+)?\z/
        return TYPE_DOUBLE
      when /\Asize_t(?:\s+\w+)?\z/
        return TYPE_SIZE_T
      when /\Assize_t(?:\s+\w+)?\z/
        return TYPE_SSIZE_T
      when /\Aptrdiff_t(?:\s+\w+)?\z/
        return TYPE_PTRDIFF_T
      when /\Aintptr_t(?:\s+\w+)?\z/
        return TYPE_INTPTR_T
      when /\Auintptr_t(?:\s+\w+)?\z/
        return TYPE_UINTPTR_T
      when "bool"
        return TYPE_BOOL
      when /\*/, /\[[\s\d]*\]/
        return TYPE_VOIDP
      when "..."
        return TYPE_VARIADIC
      else
        ty = ty.split(' ', 2)[0]
        if( tymap[ty] )
          return parse_ctype(tymap[ty], tymap)
        else
          raise(DLError, "unknown type: #{ty}")
        end
      end
    end

    private

    def split_arguments(arguments, sep=',')
      return [] if arguments.strip == 'void'
      arguments.scan(/([\w\*\s]+\(\*\w*\)\(.*?\)|[\w\*\s\[\]]+|\.\.\.)(?:#{sep}\s*|\z)/).collect {|m| m[0]}
    end

    def compact(signature)
      signature.gsub(/\s+/, ' ').gsub(/\s*([\(\)\[\]\*,;])\s*/, '\1').strip
    end

  end
end
