module MessagePack
  class Factory
    # see ext for other methods

    def register_type(type, klass, options = { packer: :to_msgpack_ext, unpacker: :from_msgpack_ext })
      raise FrozenError, "can't modify frozen MessagePack::Factory" if frozen?

      if options
        options = options.dup
        case packer = options[:packer]
        when nil, Proc
          # all good
        when String, Symbol
          options[:packer] = packer.to_sym.to_proc
        when Method
          options[:packer] = packer.to_proc
        when packer.respond_to?(:call)
          options[:packer] = packer.method(:call).to_proc
        else
          raise ::TypeError, "expected :packer argument to be a callable object, got: #{packer.inspect}"
        end

        case unpacker = options[:unpacker]
        when nil, Proc
          # all good
        when String, Symbol
          options[:unpacker] = klass.method(unpacker).to_proc
        when Method
          options[:unpacker] = unpacker.to_proc
        when packer.respond_to?(:call)
          options[:unpacker] = unpacker.method(:call).to_proc
        else
          raise ::TypeError, "expected :unpacker argument to be a callable object, got: #{unpacker.inspect}"
        end
      end

      register_type_internal(type, klass, options)
    end

    # [ {type: id, class: Class(or nil), packer: arg, unpacker: arg}, ... ]
    def registered_types(selector=:both)
      packer, unpacker = registered_types_internal
      # packer: Class -> [tid, proc, _flags]
      # unpacker: tid -> [klass, proc, _flags]

      list = []

      case selector
      when :both
        packer.each_pair do |klass, ary|
          type = ary[0]
          packer_proc = ary[1]
          unpacker_proc = nil
          if unpacker.has_key?(type)
            unpacker_proc = unpacker.delete(type)[1]
          end
          list << {type: type, class: klass, packer: packer_proc, unpacker: unpacker_proc}
        end

        # unpacker definition only
        unpacker.each_pair do |type, ary|
          list << {type: type, class: ary[0], packer: nil, unpacker: ary[1]}
        end

      when :packer
        packer.each_pair do |klass, ary|
          if ary[1]
            list << {type: ary[0], class: klass, packer: ary[1]}
          end
        end

      when :unpacker
        unpacker.each_pair do |type, ary|
          if ary[1]
            list << {type: type, class: ary[0], unpacker: ary[1]}
          end
        end

      else
        raise ArgumentError, "invalid selector #{selector}"
      end

      list.sort{|a, b| a[:type] <=> b[:type] }
    end

    def type_registered?(klass_or_type, selector=:both)
      case klass_or_type
      when Class
        klass = klass_or_type
        registered_types(selector).any?{|entry| klass <= entry[:class] }
      when Integer
        type = klass_or_type
        registered_types(selector).any?{|entry| type == entry[:type] }
      else
        raise ArgumentError, "class or type id"
      end
    end

    def load(src, param = nil)
      unpacker = nil

      if src.is_a? String
        unpacker = unpacker(param)
        unpacker.feed(src)
      else
        unpacker = unpacker(src, param)
      end

      unpacker.full_unpack
    end
    alias :unpack :load

    def dump(v, *rest)
      packer = packer(*rest)
      packer.write(v)
      packer.full_pack
    end
    alias :pack :dump

    def pool(size = 1, **options)
      Pool.new(
        frozen? ? self : dup.freeze,
        size,
        options.empty? ? nil : options,
      )
    end

    class Pool
      if RUBY_ENGINE == "ruby"
        class MemberPool
          def initialize(size, &block)
            @size = size
            @new_member = block
            @members = []
          end

          def with
            member = @members.pop || @new_member.call
            begin
              yield member
            ensure
              # If the pool is already full, we simply drop the extra member.
              # This is because contrary to a connection pool, creating an extra instance
              # is extremely unlikely to cause some kind of resource exhaustion.
              #
              # We could cycle the members (keep the newer one) but first It's more work and second
              # the older member might have been created pre-fork, so it might be at least partially
              # in shared memory.
              if member && @members.size < @size
                member.reset
                @members << member
              end
            end
          end
        end
      else
        class MemberPool
          def initialize(size, &block)
            @size = size
            @new_member = block
            @members = []
            @mutex = Mutex.new
          end

          def with
            member = @mutex.synchronize { @members.pop } || @new_member.call
            begin
              yield member
            ensure
              member.reset
              @mutex.synchronize do
                if member && @members.size < @size
                  @members << member
                end
              end
            end
          end
        end
      end

      def initialize(factory, size, options = nil)
        options = nil if !options || options.empty?
        @factory = factory
        @packers = MemberPool.new(size) { factory.packer(options).freeze }
        @unpackers = MemberPool.new(size) { factory.unpacker(options).freeze }
      end

      def load(data)
        @unpackers.with do |unpacker|
          unpacker.feed(data)
          unpacker.full_unpack
        end
      end

      def dump(object)
        @packers.with do |packer|
          packer.write(object)
          packer.full_pack
        end
      end

      def unpacker(&block)
        @unpackers.with(&block)
      end

      def packer(&block)
        @packers.with(&block)
      end
    end
  end
end
