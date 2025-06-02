module BinData
  # Raised when #lookup fails.
  class UnRegisteredTypeError < StandardError; end

  # This registry contains a register of name -> class mappings.
  #
  # Numerics (integers and floating point numbers) have an endian property as
  # part of their name (e.g. int32be, float_le).
  #
  # Classes can be looked up based on their full name or an abbreviated +name+
  # with +hints+.
  #
  # There are two hints supported, :endian and :search_prefix.
  #
  #   #lookup("int32", { endian: :big }) will return Int32Be.
  #
  #   #lookup("my_type", { search_prefix: :ns }) will return NsMyType.
  #
  # Names are stored in under_score_style, not camelCase.
  class Registry
    def initialize
      @registry = {}
    end

    def register(name, class_to_register)
      return if name.nil? || class_to_register.nil?

      formatted_name = underscore_name(name)
      warn_if_name_is_already_registered(formatted_name, class_to_register)

      @registry[formatted_name] = class_to_register
    end

    def unregister(name)
      @registry.delete(underscore_name(name))
    end

    def lookup(name, hints = {})
      the_class = @registry[normalize_name(name, hints)]
      if the_class
        the_class
      elsif @registry[normalize_name(name, hints.merge(endian: :big))]
        raise(UnRegisteredTypeError, "#{name}, do you need to specify endian?")
      else
        raise(UnRegisteredTypeError, name)
      end
    end

    # Convert CamelCase +name+ to underscore style.
    def underscore_name(name)
      name
        .to_s
        .sub(/.*::/, "")
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr('-', '_')
        .downcase
    end

    #---------------
    private

    def normalize_name(name, hints)
      name = underscore_name(name)

      if !registered?(name)
        search_prefix = [""] + Array(hints[:search_prefix])
        search_prefix.each do |prefix|
          nwp = name_with_prefix(name, prefix)
          if registered?(nwp)
            name = nwp
            break
          end

          nwe = name_with_endian(nwp, hints[:endian])
          if registered?(nwe)
            name = nwe
            break
          end
        end
      end

      name
    end

    def name_with_prefix(name, prefix)
      prefix = prefix.to_s.chomp('_')
      if prefix == ""
        name
      else
        "#{prefix}_#{name}"
      end
    end

    def name_with_endian(name, endian)
      return name if endian.nil?

      suffix = (endian == :little) ? 'le' : 'be'
      if /^u?int\d+$/.match?(name)
        name + suffix
      else
        name + '_' + suffix
      end
    end

    def registered?(name)
      register_dynamic_class(name) unless @registry.key?(name)

      @registry.key?(name)
    end

    def register_dynamic_class(name)
      if /^u?int\d+(le|be)$/.match?(name) || /^s?bit\d+(le)?$/.match?(name)
        class_name = name.gsub(/(?:^|_)(.)/) { $1.upcase }
        begin
          # call const_get for side effects
          BinData.const_get(class_name)
        rescue NameError
        end
      end
    end

    def warn_if_name_is_already_registered(name, class_to_register)
      prev_class = @registry[name]
      if prev_class && prev_class != class_to_register
        Kernel.warn "warning: replacing registered class #{prev_class} " \
             "with #{class_to_register}"
      end
    end
  end

  # A singleton registry of all registered classes.
  RegisteredClasses = Registry.new
end
