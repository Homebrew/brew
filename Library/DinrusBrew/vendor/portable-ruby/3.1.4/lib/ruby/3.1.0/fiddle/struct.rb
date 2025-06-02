# frozen_string_literal: true
require 'fiddle'
require 'fiddle/value'
require 'fiddle/pack'

module Fiddle
  # A base class for objects representing a C structure
  class CStruct
    include Enumerable

    # accessor to Fiddle::CStructEntity
    def CStruct.entity_class
      CStructEntity
    end

    def self.offsetof(name, members, types) # :nodoc:
      offset = 0
      worklist = name.split('.')
      this_type = self
      while search_name = worklist.shift
        index = 0
        member_index = members.index(search_name)

        unless member_index
          # Possibly a sub-structure
          member_index = members.index { |member_name, _|
            member_name == search_name
          }
          return unless member_index
        end

        types.each { |type, count = 1|
          orig_offset = offset
          if type.respond_to?(:entity_class)
            align = type.alignment
            type_size = type.size
          else
            align = PackInfo::ALIGN_MAP[type]
            type_size = PackInfo::SIZE_MAP[type]
          end

          # Unions shouldn't advance the offset
          if this_type.entity_class == CUnionEntity
            type_size = 0
          end

          offset = PackInfo.align(orig_offset, align)

          if worklist.empty?
            return offset if index == member_index
          else
            if index == member_index
              subtype = types[member_index]
              members = subtype.members
              types = subtype.types
              this_type = subtype
              break
            end
          end

          offset += (type_size * count)
          index += 1
        }
      end
      nil
    end

    def each
      return enum_for(__function__) unless block_given?

      self.class.members.each do |name,|
        yield(self[name])
      end
    end

    def each_pair
      return enum_for(__function__) unless block_given?

      self.class.members.each do |name,|
        yield(name, self[name])
      end
    end

    def to_h
      hash = {}
      each_pair do |name, value|
        hash[name] = unstruct(value)
      end
      hash
    end

    def replace(another)
      if another.nil?
        self.class.members.each do |name,|
          self[name] = nil
        end
      elsif another.respond_to?(:each_pair)
        another.each_pair do |name, value|
          self[name] = value
        end
      else
        another.each do |name, value|
          self[name] = value
        end
      end
      self
    end

    private
    def unstruct(value)
      case value
      when CStruct
        value.to_h
      when Array
        value.collect do |v|
          unstruct(v)
        end
      else
        value
      end
    end
  end

  # A base class for objects representing a C union
  class CUnion
    # accessor to Fiddle::CUnionEntity
    def CUnion.entity_class
      CUnionEntity
    end

    def self.offsetof(name, members, types) # :nodoc:
      0
    end
  end

  # Wrapper for arrays within a struct
  class StructArray < Array
    include ValueUtil

    def initialize(ptr, type, initial_values)
      @ptr = ptr
      @type = type
      @is_struct = @type.respond_to?(:entity_class)
      if @is_struct
        super(initial_values)
      else
        @size = Fiddle::PackInfo::SIZE_MAP[type]
        @pack_format = Fiddle::PackInfo::PACK_MAP[type]
        super(initial_values.collect { |v| unsigned_value(v, type) })
      end
    end

    def to_ptr
      @ptr
    end

    def []=(index, value)
      if index < 0 || index >= size
        raise IndexError, 'index %d outside of array bounds 0...%d' % [index, size]
      end

      if @is_struct
        self[index].replace(value)
      else
        to_ptr[index * @size, @size] = [value].pack(@pack_format)
        super(index, value)
      end
    end
  end

  # Used to construct C classes (CUnion, CStruct, etc)
  #
  # Fiddle::Importer#struct and Fiddle::Importer#union wrap this functionality in an
  # easy-to-use manner.
  module CStructBuilder
    # Construct a new class given a C:
    # * class +klass+ (CUnion, CStruct, or other that provide an
    #   #entity_class)
    # * +types+ (Fiddle::TYPE_INT, Fiddle::TYPE_SIZE_T, etc., see the C types
    #   constants)
    # * corresponding +members+
    #
    # Fiddle::Importer#struct and Fiddle::Importer#union wrap this functionality in an
    # easy-to-use manner.
    #
    # Examples:
    #
    #   require 'fiddle/struct'
    #   require 'fiddle/cparser'
    #
    #   include Fiddle::CParser
    #
    #   types, members = parse_struct_signature(['int i','char c'])
    #
    #   MyStruct = Fiddle::CStructBuilder.create(Fiddle::CUnion, types, members)
    #
    #   MyStruct.malloc(Fiddle::RUBY_FREE) do |obj|
    #     ...
    #   end
    #
    #   obj = MyStruct.malloc(Fiddle::RUBY_FREE)
    #   begin
    #     ...
    #   ensure
    #     obj.call_free
    #   end
    #
    #   obj = MyStruct.malloc
    #   begin
    #     ...
    #   ensure
    #     Fiddle.free obj.to_ptr
    #   end
    #
    def create(klass, types, members)
      new_class = Class.new(klass){
        define_method(:initialize){|addr, func = nil|
          if addr.is_a?(self.class.entity_class)
            @entity = addr
          else
            @entity = self.class.entity_class.new(addr, types, func)
          end
          @entity.assign_names(members)
        }
        define_method(:[]) { |*args| @entity.send(:[], *args) }
        define_method(:[]=) { |*args| @entity.send(:[]=, *args) }
        define_method(:to_ptr){ @entity }
        define_method(:to_i){ @entity.to_i }
        define_singleton_method(:types) { types }
        define_singleton_method(:members) { members }

        # Return the offset of a struct member given its name.
        # For example:
        #
        #     MyStruct = struct [
        #       "int64_t i",
        #       "char c",
        #     ]
        #
        #     MyStruct.offsetof("i") # => 0
        #     MyStruct.offsetof("c") # => 8
        #
        define_singleton_method(:offsetof) { |name|
          klass.offsetof(name, members, types)
        }
        members.each{|name|
          name = name[0] if name.is_a?(Array) # name is a nested struct
          next if method_defined?(name)
          define_method(name){ @entity[name] }
          define_method(name + "="){|val| @entity[name] = val }
        }
        entity_class = klass.entity_class
        alignment = entity_class.alignment(types)
        size = entity_class.size(types)
        define_singleton_method(:alignment) { alignment }
        define_singleton_method(:size) { size }
        define_singleton_method(:malloc) do |func=nil, &block|
          if block
            entity_class.malloc(types, func, size) do |entity|
              block.call(new(entity))
            end
          else
            new(entity_class.malloc(types, func, size))
          end
        end
      }
      return new_class
    end
    module_function :create
  end

  # A pointer to a C structure
  class CStructEntity < Fiddle::Pointer
    include PackInfo
    include ValueUtil

    def CStructEntity.alignment(types)
      max = 1
      types.each do |type, count = 1|
        if type.respond_to?(:entity_class)
          n = type.alignment
        else
          n = ALIGN_MAP[type]
        end
        max = n if n > max
      end
      max
    end

    # Allocates a C struct with the +types+ provided.
    #
    # See Fiddle::Pointer.malloc for memory management issues.
    def CStructEntity.malloc(types, func = nil, size = size(types), &block)
      if block_given?
        super(size, func) do |struct|
          struct.set_ctypes types
          yield struct
        end
      else
        struct = super(size, func)
        struct.set_ctypes types
        struct
      end
    end

    # Returns the offset for the packed sizes for the given +types+.
    #
    #   Fiddle::CStructEntity.size(
    #     [ Fiddle::TYPE_DOUBLE,
    #       Fiddle::TYPE_INT,
    #       Fiddle::TYPE_CHAR,
    #       Fiddle::TYPE_VOIDP ]) #=> 24
    def CStructEntity.size(types)
      offset = 0

      max_align = types.map { |type, count = 1|
        last_offset = offset

        if type.respond_to?(:entity_class)
          align = type.alignment
          type_size = type.size
        else
          align = PackInfo::ALIGN_MAP[type]
          type_size = PackInfo::SIZE_MAP[type]
        end
        offset = PackInfo.align(last_offset, align) +
                 (type_size * count)

        align
      }.max

      PackInfo.align(offset, max_align)
    end

    # Wraps the C pointer +addr+ as a C struct with the given +types+.
    #
    # When the instance is garbage collected, the C function +func+ is called.
    #
    # See also Fiddle::Pointer.new
    def initialize(addr, types, func = nil)
      if func && addr.is_a?(Pointer) && addr.free
        raise ArgumentError, 'free function specified on both underlying struct Pointer and when creating a CStructEntity - who do you want to free this?'
      end
      set_ctypes(types)
      super(addr, @size, func)
    end

    # Set the names of the +members+ in this C struct
    def assign_names(members)
      @members = []
      @nested_structs = {}
      members.each_with_index do |member, index|
        if member.is_a?(Array) # nested struct
          member_name = member[0]
          struct_type, struct_count = @ctypes[index]
          if struct_count.nil?
            struct = struct_type.new(to_i + @offset[index])
          else
            structs = struct_count.times.map do |i|
              struct_type.new(to_i + @offset[index] + i * struct_type.size)
            end
            struct = StructArray.new(to_i + @offset[index],
                                     struct_type,
                                     structs)
          end
          @nested_structs[member_name] = struct
        else
          member_name = member
        end
        @members << member_name
      end
    end

    # Calculates the offsets and sizes for the given +types+ in the struct.
    def set_ctypes(types)
      @ctypes = types
      @offset = []
      offset = 0

      max_align = types.map { |type, count = 1|
        orig_offset = offset
        if type.respond_to?(:entity_class)
          align = type.alignment
          type_size = type.size
        else
          align = ALIGN_MAP[type]
          type_size = SIZE_MAP[type]
        end
        offset = PackInfo.align(orig_offset, align)

        @offset << offset

        offset += (type_size * count)

        align
      }.max

      @size = PackInfo.align(offset, max_align)
    end

    # Fetch struct member +name+ if only one argument is specified. If two
    # arguments are specified, the first is an offset and the second is a
    # length and this method returns the string of +length+ bytes beginning at
    # +offset+.
    #
    # Examples:
    #
    #     my_struct = struct(['int id']).malloc
    #     my_struct.id = 1
    #     my_struct['id'] # => 1
    #     my_struct[0, 4] # => "\x01\x00\x00\x00".b
    #
    def [](*args)
      return super(*args) if args.size > 1
      name = args[0]
      idx = @members.index(name)
      if( idx.nil? )
        raise(ArgumentError, "no such member: #{name}")
      end
      ty = @ctypes[idx]
      if( ty.is_a?(Array) )
        if ty.first.respond_to?(:entity_class)
          return @nested_structs[name]
        else
          r = super(@offset[idx], SIZE_MAP[ty[0]] * ty[1])
        end
      elsif ty.respond_to?(:entity_class)
        return @nested_structs[name]
      else
        r = super(@offset[idx], SIZE_MAP[ty.abs])
      end
      packer = Packer.new([ty])
      val = packer.unpack([r])
      case ty
      when Array
        case ty[0]
        when TYPE_VOIDP
          val = val.collect{|v| Pointer.new(v)}
        end
      when TYPE_VOIDP
        val = Pointer.new(val[0])
      else
        val = val[0]
      end
      if( ty.is_a?(Integer) && (ty < 0) )
        return unsigned_value(val, ty)
      elsif( ty.is_a?(Array) && (ty[0] < 0) )
        return StructArray.new(self + @offset[idx], ty[0], val)
      else
        return val
      end
    end

    # Set struct member +name+, to value +val+. If more arguments are
    # specified, writes the string of bytes to the memory at the given
    # +offset+ and +length+.
    #
    # Examples:
    #
    #     my_struct = struct(['int id']).malloc
    #     my_struct['id'] = 1
    #     my_struct[0, 4] = "\x01\x00\x00\x00".b
    #     my_struct.id # => 1
    #
    def []=(*args)
      return super(*args) if args.size > 2
      name, val = *args
      name = name.to_s if name.is_a?(Symbol)
      nested_struct = @nested_structs[name]
      if nested_struct
        if nested_struct.is_a?(StructArray)
          if val.nil?
            nested_struct.each do |s|
              s.replace(nil)
            end
          else
            val.each_with_index do |v, i|
              nested_struct[i] = v
            end
          end
        else
          nested_struct.replace(val)
        end
        return val
      end
      idx = @members.index(name)
      if( idx.nil? )
        raise(ArgumentError, "no such member: #{name}")
      end
      ty  = @ctypes[idx]
      packer = Packer.new([ty])
      val = wrap_arg(val, ty, [])
      buff = packer.pack([val].flatten())
      super(@offset[idx], buff.size, buff)
      if( ty.is_a?(Integer) && (ty < 0) )
        return unsigned_value(val, ty)
      elsif( ty.is_a?(Array) && (ty[0] < 0) )
        return val.collect{|v| unsigned_value(v,ty[0])}
      else
        return val
      end
    end

    undef_method :size=
    def to_s() # :nodoc:
      super(@size)
    end
  end

  # A pointer to a C union
  class CUnionEntity < CStructEntity
    include PackInfo

    # Returns the size needed for the union with the given +types+.
    #
    #   Fiddle::CUnionEntity.size(
    #     [ Fiddle::TYPE_DOUBLE,
    #       Fiddle::TYPE_INT,
    #       Fiddle::TYPE_CHAR,
    #       Fiddle::TYPE_VOIDP ]) #=> 8
    def CUnionEntity.size(types)
      types.map { |type, count = 1|
        if type.respond_to?(:entity_class)
          type.size * count
        else
          PackInfo::SIZE_MAP[type] * count
        end
      }.max
    end

    # Calculate the necessary offset and for each union member with the given
    # +types+
    def set_ctypes(types)
      @ctypes = types
      @offset = Array.new(types.length, 0)
      @size   = self.class.size types
    end
  end
end
