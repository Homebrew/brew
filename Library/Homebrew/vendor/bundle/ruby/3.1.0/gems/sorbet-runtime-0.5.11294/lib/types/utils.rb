# frozen_string_literal: true
# typed: true

module T::Utils
  module Private
    def self.coerce_and_check_module_types(val, check_val, check_module_type)
      # rubocop:disable Style/CaseLikeIf
      if val.is_a?(T::Types::Base)
        if val.is_a?(T::Private::Types::TypeAlias)
          val.aliased_type
        else
          val
        end
      elsif val.is_a?(Module)
        if check_module_type && check_val.is_a?(val)
          nil
        else
          T::Types::Simple::Private::Pool.type_for_module(val)
        end
      elsif val.is_a?(::Array)
        T::Types::FixedArray.new(val)
      elsif val.is_a?(::Hash)
        T::Types::FixedHash.new(val)
      elsif val.is_a?(T::Private::Methods::DeclBuilder)
        T::Private::Methods.finalize_proc(val.decl)
      elsif val.is_a?(::T::Enum)
        T::Types::TEnum.new(val)
      elsif val.is_a?(::String)
        raise "Invalid String literal for type constraint. Must be an #{T::Types::Base}, a " \
              "class/module, or an array. Got a String with value `#{val}`."
      else
        raise "Invalid value for type constraint. Must be an #{T::Types::Base}, a " \
              "class/module, or an array. Got a `#{val.class}`."
      end
      # rubocop:enable Style/CaseLikeIf
    end
  end

  # Used to convert from a type specification to a `T::Types::Base`.
  def self.coerce(val)
    Private.coerce_and_check_module_types(val, nil, false)
  end

  # Dynamically confirm that `value` is recursively a valid value of
  # type `type`, including recursively through collections. Note that
  # in some cases this runtime check can be very expensive, especially
  # with large collections of objects.
  def self.check_type_recursive!(value, type)
    T::Private::Casts.cast_recursive(value, type, "T.check_type_recursive!")
  end

  # Returns the set of all methods (public, protected, private) defined on a module or its
  # ancestors, excluding Object and its ancestors. Overrides of methods from Object (and its
  # ancestors) are included.
  def self.methods_excluding_object(mod)
    # We can't just do mod.instance_methods - Object.instance_methods, because that would leave out
    # any methods from Object that are overridden in mod.
    mod.ancestors.flat_map do |ancestor|
      # equivalent to checking Object.ancestors.include?(ancestor)
      next [] if Object <= ancestor
      ancestor.instance_methods(false) + ancestor.private_instance_methods(false)
    end.uniq
  end

  # Returns the signature for the `UnboundMethod`, or nil if it's not sig'd
  #
  # @example T::Utils.signature_for_method(x.method(:foo))
  def self.signature_for_method(method)
    T::Private::Methods.signature_for_method(method)
  end

  # Returns the signature for the instance method on the supplied module, or nil if it's not found or not typed.
  #
  # @example T::Utils.signature_for_instance_method(MyClass, :my_method)
  def self.signature_for_instance_method(mod, method_name)
    T::Private::Methods.signature_for_method(mod.instance_method(method_name))
  end

  def self.wrap_method_with_call_validation_if_needed(mod, method_sig, original_method)
    T::Private::Methods::CallValidation.wrap_method_if_needed(mod, method_sig, original_method)
  end

  # Unwraps all the sigs.
  def self.run_all_sig_blocks(force_type_init: true)
    T::Private::Methods.run_all_sig_blocks(force_type_init: force_type_init)
  end

  # Return the underlying type for a type alias. Otherwise returns type.
  def self.resolve_alias(type)
    case type
    when T::Private::Types::TypeAlias
      type.aliased_type
    else
      type
    end
  end

  # Give a type which is a subclass of T::Types::Base, determines if the type is a simple nilable type (union of NilClass and something else).
  # If so, returns the T::Types::Base of the something else. Otherwise, returns nil.
  def self.unwrap_nilable(type)
    case type
    when T::Types::Union
      type.unwrap_nilable
    else
      nil
    end
  end

  # Returns the arity of a method, unwrapping the sig if needed
  def self.arity(method)
    arity = method.arity
    return arity if arity != -1 || method.is_a?(Proc)
    sig = T::Private::Methods.signature_for_method(method)
    sig ? sig.method.arity : arity
  end

  # Elide the middle of a string as needed and replace it with an ellipsis.
  # Keep the given number of characters at the start and end of the string.
  #
  # This method operates on string length, not byte length.
  #
  # If the string is shorter than the requested truncation length, return it
  # without adding an ellipsis. This method may return a longer string than
  # the original if the characters removed are shorter than the ellipsis.
  #
  # @param [String] str
  #
  # @param [Fixnum] start_len The length of string before the ellipsis
  # @param [Fixnum] end_len The length of string after the ellipsis
  #
  # @param [String] ellipsis The string to add in place of the elided text
  #
  # @return [String]
  #
  def self.string_truncate_middle(str, start_len, end_len, ellipsis='...')
    return unless str

    raise ArgumentError.new('must provide start_len') unless start_len
    raise ArgumentError.new('must provide end_len') unless end_len

    raise ArgumentError.new('start_len must be >= 0') if start_len < 0
    raise ArgumentError.new('end_len must be >= 0') if end_len < 0

    str = str.to_s
    return str if str.length <= start_len + end_len

    start_part = str[0...start_len - ellipsis.length]
    end_part = end_len == 0 ? '' : str[-end_len..-1]

    "#{start_part}#{ellipsis}#{end_part}"
  end

  def self.lift_enum(enum)
    unless enum.is_a?(T::Types::Enum)
      raise ArgumentError.new("#{enum.inspect} is not a T.deprecated_enum")
    end

    classes = enum.values.map(&:class).uniq
    if classes.empty?
      T.untyped
    elsif classes.length > 1
      T::Types::Union.new(classes)
    else
      T::Types::Simple::Private::Pool.type_for_module(classes.first)
    end
  end

  module Nilable
    # :is_union_type, T::Boolean: whether the type is an T::Types::Union type
    # :non_nilable_type, Class: if it is an T.nilable type, the corresponding underlying type; otherwise, nil.
    TypeInfo = Struct.new(:is_union_type, :non_nilable_type)

    NIL_TYPE = T::Utils.coerce(NilClass)

    def self.get_type_info(prop_type)
      if prop_type.is_a?(T::Types::Union)
        non_nilable_type = prop_type.unwrap_nilable
        if non_nilable_type.is_a?(T::Types::Simple)
          non_nilable_type = non_nilable_type.raw_type
        end
        TypeInfo.new(true, non_nilable_type)
      else
        TypeInfo.new(false, nil)
      end
    end

    # Get the underlying type inside prop_type:
    #  - if the type is A, the function returns A
    #  - if the type is T.nilable(A), the function returns A
    def self.get_underlying_type(prop_type)
      if prop_type.is_a?(T::Types::Union)
        non_nilable_type = prop_type.unwrap_nilable
        if non_nilable_type.is_a?(T::Types::Simple)
          non_nilable_type = non_nilable_type.raw_type
        end
        non_nilable_type || prop_type
      elsif prop_type.is_a?(T::Types::Simple)
        prop_type.raw_type
      else
        prop_type
      end
    end

    # The difference between this function and the above function is that the Sorbet type, like T::Types::Simple
    # is preserved.
    def self.get_underlying_type_object(prop_type)
      T::Utils.unwrap_nilable(prop_type) || prop_type
    end

    def self.is_union_with_nilclass(prop_type)
      case prop_type
      when T::Types::Union
        prop_type.types.include?(NIL_TYPE)
      else
        false
      end
    end
  end
end
