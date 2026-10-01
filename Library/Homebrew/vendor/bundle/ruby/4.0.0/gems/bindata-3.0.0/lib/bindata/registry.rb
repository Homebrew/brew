module BinData
  # Raised when #lookup fails.
  class UnRegisteredTypeError < StandardError; end

  # This registry contains a register of name -> class mappings.
  #
  # Numerics (integers and floating point numbers) have an endian property as
  # part of their name (e.g. int32be, float_le).
  #
  # Classes exist in a namespace that mirrors the Ruby module hierarchy.
  #
  # Classes can be looked up based on their full name or an abbreviated +name+
  # with +hints+.
  #
  # There are two hints supported, :endian and :search_namespace.
  #
  #   #lookup("", "int32", { endian: :big }) will return Int32Be.
  #
  #   #lookup("", "my_type", { search_namespace: :ns }) will return Ns::MyType.
  #
  # Names are stored in under_score_style, not camelCase.
  class Registry
    def initialize
      @registry = {}
      @backwards_compatible_registry = {}
    end

    def register(namespace, name, class_to_register)
      return if namespace.nil? || name.nil? || class_to_register.nil?

      search = name_with_prefix(name, namespace)
      warn_if_name_is_already_registered(search, class_to_register)

      @registry[search] = class_to_register
      @backwards_compatible_registry[underscore_name(name)] = search
    end

    def unregister(namespace, name)
      search = name_with_prefix(name, namespace)

      @registry.delete(search)
      @backwards_compatible_registry.delete(underscore_name(name))
    end

    def lookup(namespace, name, hints = {})
      search_names(namespace, name, hints).each do |search|
        register_dynamic_class(search)
        if @registry.has_key?(search)
          return @registry[search]
        end
      end

      # give the user a hint if the endian keyword is missing
      search_names(namespace, name, hints.merge(endian: :big)).each do |search|
        register_dynamic_class(search)
        if @registry.has_key?(search)
          raise(UnRegisteredTypeError, "#{name}, do you need to specify endian?")
        end
      end

      raise(UnRegisteredTypeError, name)
    end

    # Convert CamelCase +name+ to underscore style.
    def underscore_name(name)
      name
        .to_s
        .gsub(/::/, "_")
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr('-', '_')
        .downcase
    end

    #---------------
    private

    def search_names(namespace, name, hints)
      searches = backwards_compatible_search_names(name, hints)
      return searches unless searches.empty?

      searches = []

      # prioritise BinData classes
      nwp = name_with_prefix(name, "BinData")
      nwe = name_with_endian(nwp, hints[:endian])
      searches << nwp
      searches << nwe if nwe

      ns = underscore_name(namespace)
      loop do
        search_prefix = [""] + Array(hints[:search_namespace])
        search_prefix.each do |prefix|
          nwp = name_with_prefix(name, name_with_prefix(prefix, ns))
          nwe = name_with_endian(nwp, hints[:endian])

          searches << nwp
          searches << nwe if nwe
        end

        break if ns == ""
        ns.sub!(/(?:^|_)[^_]*$/, "")
      end

      searches
    end

    # The old way of providing namespaces was to prefix the class name.
    # Here we provide the backward compatibility for existing code.
    def backwards_compatible_search_names(name, hints)
      return [] unless hints.has_key?(:search_prefix)

      searches = []
      search_prefix = Array(hints[:search_prefix])
      search_prefix.each do |prefix|
        nwp = name_with_prefix(name, prefix)
        nwe = name_with_endian(nwp, hints[:endian])

        found_search = @backwards_compatible_registry[nwp]
        searches << found_search if found_search

        if nwe
          found_search = @backwards_compatible_registry[nwe]
          searches << found_search if found_search
        end
      end

      searches
    end

    def name_with_prefix(name, prefix)
      name = underscore_name(name)
      prefix = underscore_name(prefix).chomp('_')
      if prefix == ""
        name
      else
        "#{prefix}_#{name}"
      end
    end

    def name_with_endian(name, endian)
      return nil if endian.nil?

      suffix = (endian == :little) ? 'le' : 'be'
      if /^bin_data_u?int\d+$/.match?(name)
        name + suffix
      else
        name + '_' + suffix
      end
    end

    def register_dynamic_class(name)
      return unless /^bin_data_/ =~ name

      if /^bin_data_u?int\d+(le|be)$/.match?(name) || /^bin_data_s?bit\d+(le)?$/.match?(name)
        base_name = name.sub(/^bin_data_/, "")
        class_name = base_name.gsub(/(?:^|_)(.)/) { $1.upcase }
        begin
          # call const_get for side effect of creating class
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
