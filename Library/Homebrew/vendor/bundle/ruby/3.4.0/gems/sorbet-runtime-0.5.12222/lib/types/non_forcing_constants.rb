# frozen_string_literal: true
# typed: strict

module T::NonForcingConstants
  # NOTE: This method is documented on the RBI in Sorbet's payload, so that it
  # shows up in the hover/completion documentation via LSP.
  T::Sig::WithoutRuntime.sig { params(val: BasicObject, klass: String).returns(T::Boolean) }
  def self.non_forcing_is_a?(val, klass)
    method_name = "T::NonForcingConstants.non_forcing_is_a?"
    if klass.empty?
      raise ArgumentError.new("The string given to `#{method_name}` must not be empty")
    end

    current_klass = T.let(nil, T.nilable(Module))
    current_prefix = T.let(nil, T.nilable(String))

    parts = klass.split('::')
    parts.each do |part|
      if current_klass.nil?
        # First iteration
        if part != ""
          raise ArgumentError.new("The string given to `#{method_name}` must be an absolute constant reference that starts with `::`")
        end

        current_klass = Object
        current_prefix = ''

        # if this had a :: prefix, then there's no more loading to
        # do---skip to the next one
        next
      end

      if current_klass.autoload?(part)
        # There's an autoload registered for that constant, which means it's not
        # yet loaded. `value` can't be an instance of something not yet loaded.
        return false
      end

      # Sorbet guarantees that the string is an absolutely resolved name.
      search_inheritance_chain = false
      if !current_klass.const_defined?(part, search_inheritance_chain)
        return false
      end

      current_klass = current_klass.const_get(part)
      current_prefix = "#{current_prefix}::#{part}"

      if !Module.===(current_klass)
        raise ArgumentError.new("#{current_prefix} is not a class or module")
      end
    end

    current_klass.===(val)
  end
end
