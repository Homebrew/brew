module MessagePack
  class Unpacker
    # see ext for other methods

    # The semantic of duping an unpacker is just too weird.
    undef_method :dup
    undef_method :clone

    def register_type(type, klass = nil, method_name = nil, &block)
      if klass && method_name
        block = klass.method(method_name).to_proc
      elsif !block_given?
        raise ArgumentError, "register_type takes either 3 arguments or a block"
      end
      register_type_internal(type, klass, block)
    end

    def registered_types
      list = []

      registered_types_internal.each_pair do |type, ary|
        list << {type: type, class: ary[0], unpacker: ary[1]}
      end

      list.sort{|a, b| a[:type] <=> b[:type] }
    end

    def type_registered?(klass_or_type)
      case klass_or_type
      when Class
        klass = klass_or_type
        registered_types.any?{|entry| klass == entry[:class] }
      when Integer
        type = klass_or_type
        registered_types.any?{|entry| type == entry[:type] }
      else
        raise ArgumentError, "class or type id"
      end
    end
  end
end
