module MessagePack
  class Packer
    # see ext for other methods

    # The semantic of duping a packer is just too weird.
    undef_method :dup
    undef_method :clone

    def register_type(type, klass, method_name = nil, &block)
      raise ArgumentError, "expected Module/Class got: #{klass.inspect}" unless klass.is_a?(Module)
      register_type_internal(type, klass, block || method_name.to_proc)
    end

    def registered_types
      list = []

      registered_types_internal.each_pair do |klass, ary|
        list << {type: ary[0], class: klass, packer: ary[1]}
      end

      list.sort{|a, b| a[:type] <=> b[:type] }
    end

    def type_registered?(klass_or_type)
      case klass_or_type
      when Class
        klass = klass_or_type
        registered_types.any?{|entry| klass <= entry[:class] }
      when Integer
        type = klass_or_type
        registered_types.any?{|entry| type == entry[:type] }
      else
        raise ArgumentError, "class or type id"
      end
    end
  end
end
