module RubyVM::RJIT
  # Every class under this namespace is a pointer. Even if the type is
  # immediate, it shouldn't be dereferenced until `*` is called.
  module CPointer
    # Note: We'd like to avoid alphabetic method names to avoid a conflict
    # with member methods. to_i and to_s are considered an exception.
    class Struct
      # @param name [String]
      # @param sizeof [Integer]
      # @param members [Hash{ Symbol => [RubyVM::RJIT::CType::*, Integer, TrueClass] }]
      def initialize(addr, sizeof, members)
        @addr = addr
        @sizeof = sizeof
        @members = members
      end

      # Get a raw address
      def to_i
        @addr
      end

      # Serialized address for generated code
      def to_s
        "0x#{@addr.to_s(16)}"
      end

      # Pointer diff
      def -(struct)
        raise ArgumentError if self.class != struct.class
        (@addr - struct.to_i) / @sizeof
      end

      # Primitive API that does no automatic dereference
      # TODO: remove this?
      # @param member [Symbol]
      def [](member)
        type, offset = @members.fetch(member)
        type.new(@addr + offset / 8)
      end

      private

      # @param member [Symbol]
      # @param value [Object]
      def []=(member, value)
        type, offset = @members.fetch(member)
        type[@addr + offset / 8] = value
      end

      # @param size [Integer]
      # @param members [Hash{ Symbol => [Integer, RubyVM::RJIT::CType::*] }]
      def self.define(size, members)
        Class.new(self) do
          # Return the size of this type
          define_singleton_method(:size) { size }

          # Return the offset to a field
          define_singleton_method(:offsetof) do |field, *fields|
            member, offset = members.fetch(field)
            offset /= 8
            unless fields.empty?
              offset += member.offsetof(*fields)
            end
            offset
          end

          # Return member names
          define_singleton_method(:members) { members.keys }

          define_method(:initialize) do |addr = nil|
            if addr.nil? # TODO: get rid of this feature later
              addr = Fiddle.malloc(size)
            end
            super(addr, size, members)
          end

          members.each do |member, (type, offset, to_ruby)|
            # Intelligent API that does automatic dereference
            define_method(member) do
              value = self[member]
              if value.respond_to?(:*)
                value = value.*
              end
              if to_ruby
                value = C.to_ruby(value)
              end
              value
            end

            define_method("#{member}=") do |value|
              if to_ruby
                value = C.to_value(value)
              end
              self[member] = value
            end
          end
        end
      end
    end

    # Note: We'd like to avoid alphabetic method names to avoid a conflict
    # with member methods. to_i is considered an exception.
    class Union
      # @param _name [String] To be used when it starts defining a union pointer class
      # @param sizeof [Integer]
      # @param members [Hash{ Symbol => RubyVM::RJIT::CType::* }]
      def initialize(addr, sizeof, members)
        @addr = addr
        @sizeof = sizeof
        @members = members
      end

      # Get a raw address
      def to_i
        @addr
      end

      # Move addr to access this pointer like an array
      def +(index)
        raise ArgumentError unless index.is_a?(Integer)
        self.class.new(@addr + index * @sizeof)
      end

      # Pointer diff
      def -(union)
        raise ArgumentError if self.class != union.class
        (@addr - union.instance_variable_get(:@addr)) / @sizeof
      end

      # @param sizeof [Integer]
      # @param members [Hash{ Symbol => RubyVM::RJIT::CType::* }]
      def self.define(sizeof, members)
        Class.new(self) do
          # Return the size of this type
          define_singleton_method(:sizeof) { sizeof }

          # Part of Struct's offsetof implementation
          define_singleton_method(:offsetof) do |field, *fields|
            member = members.fetch(field)
            offset = 0
            unless fields.empty?
              offset += member.offsetof(*fields)
            end
            offset
          end

          define_method(:initialize) do |addr|
            super(addr, sizeof, members)
          end

          members.each do |member, type|
            # Intelligent API that does automatic dereference
            define_method(member) do
              value = type.new(@addr)
              if value.respond_to?(:*)
                value = value.*
              end
              value
            end
          end
        end
      end
    end

    class Immediate
      # @param addr [Integer]
      # @param size [Integer]
      # @param pack [String]
      def initialize(addr, size, pack)
        @addr = addr
        @size = size
        @pack = pack
      end

      # Get a raw address
      def to_i
        @addr
      end

      # Move addr to addess this pointer like an array
      def +(index)
        Immediate.new(@addr + index * @size, @size, @pack)
      end

      # Dereference
      def *
        self[0]
      end

      # Array access
      def [](index)
        return nil if @addr == 0
        Fiddle::Pointer.new(@addr + index * @size)[0, @size].unpack1(@pack)
      end

      # Array set
      def []=(index, value)
        Fiddle::Pointer.new(@addr + index * @size)[0, @size] = [value].pack(@pack)
      end

      # Serialized address for generated code. Used for embedding things like body->iseq_encoded.
      def to_s
        "0x#{Integer(@addr).to_s(16)}"
      end

      # @param fiddle_type [Integer] Fiddle::TYPE_*
      def self.define(fiddle_type)
        size = Fiddle::PackInfo::SIZE_MAP.fetch(fiddle_type)
        pack = Fiddle::PackInfo::PACK_MAP.fetch(fiddle_type)

        Class.new(self) do
          define_method(:initialize) do |addr|
            super(addr, size, pack)
          end

          define_singleton_method(:size) do
            size
          end

          # Type-level []=: Used by struct fields
          define_singleton_method(:[]=) do |addr, value|
            Fiddle::Pointer.new(addr)[0, size] = [value].pack(pack)
          end
        end
      end
    end

    # -Fiddle::TYPE_CHAR Immediate with special handling of true/false
    class Bool < Immediate.define(-Fiddle::TYPE_CHAR)
      # Dereference
      def *
        return nil if @addr == 0
        super != 0
      end

      def self.[]=(addr, value)
        super(addr, value ? 1 : 0)
      end
    end

    # Basically Immediate but without #* to skip auto-dereference of structs.
    class Array
      attr_reader :type

      # @param addr [Integer]
      # @param type [Class] RubyVM::RJIT::CType::*
      def initialize(addr, type)
        @addr = addr
        @type = type
      end

      # Array access
      def [](index)
        @type.new(@addr)[index]
      end

      # Array set
      # @param index [Integer]
      # @param value [Integer, RubyVM::RJIT::CPointer::Struct] an address itself or an object that return an address with to_i
      def []=(index, value)
        @type.new(@addr)[index] = value
      end

      private

      def self.define(block)
        Class.new(self) do
          define_method(:initialize) do |addr|
            super(addr, block.call)
          end
        end
      end
    end

    class Pointer
      attr_reader :type

      # @param addr [Integer]
      # @param type [Class] RubyVM::RJIT::CType::*
      def initialize(addr, type)
        @addr = addr
        @type = type
      end

      # Move addr to addess this pointer like an array
      def +(index)
        raise ArgumentError unless index.is_a?(Integer)
        Pointer.new(@addr + index * Fiddle::SIZEOF_VOIDP, @type)
      end

      # Dereference
      def *
        return nil if dest_addr == 0
        @type.new(dest_addr)
      end

      # Array access
      def [](index)
        (self + index).*
      end

      # Array set
      # @param index [Integer]
      # @param value [Integer, RubyVM::RJIT::CPointer::Struct] an address itself or an object that return an address with to_i
      def []=(index, value)
        Fiddle::Pointer.new(@addr + index * Fiddle::SIZEOF_VOIDP)[0, Fiddle::SIZEOF_VOIDP] =
          [value.to_i].pack(Fiddle::PackInfo::PACK_MAP[Fiddle::TYPE_VOIDP])
      end

      # Get a raw address
      def to_i
        @addr
      end

      private

      def dest_addr
        Fiddle::Pointer.new(@addr)[0, Fiddle::SIZEOF_VOIDP].unpack1(Fiddle::PackInfo::PACK_MAP[Fiddle::TYPE_VOIDP])
      end

      def self.define(block)
        Class.new(self) do
          define_method(:initialize) do |addr|
            super(addr, block.call)
          end

          # Type-level []=: Used by struct fields
          # @param addr [Integer]
          # @param value [Integer, RubyVM::RJIT::CPointer::Struct] an address itself, or an object that return an address with to_i
          define_singleton_method(:[]=) do |addr, value|
            value = value.to_i
            Fiddle::Pointer.new(addr)[0, Fiddle::SIZEOF_VOIDP] = [value].pack(Fiddle::PackInfo::PACK_MAP[Fiddle::TYPE_VOIDP])
          end
        end
      end
    end

    class BitField
      # @param addr [Integer]
      # @param width [Integer]
      # @param offset [Integer]
      def initialize(addr, width, offset)
        @addr = addr
        @width = width
        @offset = offset
      end

      # Dereference
      def *
        byte = Fiddle::Pointer.new(@addr)[0, Fiddle::SIZEOF_CHAR].unpack('c').first
        if @width == 1
          bit = (1 & (byte >> @offset))
          bit == 1
        elsif @width <= 8 && @offset == 0
          bitmask = @width.times.map { |i| 1 << i }.sum
          byte & bitmask
        else
          raise NotImplementedError.new("not-implemented bit field access: width=#{@width} offset=#{@offset}")
        end
      end

      # @param width [Integer]
      # @param offset [Integer]
      def self.define(width, offset)
        Class.new(self) do
          define_method(:initialize) do |addr|
            super(addr, width, offset)
          end
        end
      end
    end

    # Give a name to a dynamic CPointer class to see it on inspect
    def self.with_class_name(prefix, name, cache: false, &block)
      return block.call if !name.nil? && name.empty?

      # Use a cached result only if cache: true
      class_name = "#{prefix}_#{name}"
      klass =
        if cache && self.const_defined?(class_name)
          self.const_get(class_name)
        else
          block.call
        end

      # Give it a name unless it's already defined
      unless self.const_defined?(class_name)
        self.const_set(class_name, klass)
      end

      klass
    end
  end
end
