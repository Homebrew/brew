# frozen_string_literal: true
# typed: false

module T::Private::Methods::CallValidation
  CallValidation = T::Private::Methods::CallValidation
  Modes = T::Private::Methods::Modes

  # Wraps a method with a layer of validation for the given type signature.
  # This wrapper is meant to be fast, and is applied by a previous wrapper,
  # which was placed by `_on_method_added`.
  #
  # @param method_sig [T::Private::Methods::Signature]
  # @return [UnboundMethod] the new wrapper method (or the original one if we didn't wrap it)
  def self.wrap_method_if_needed(mod, method_sig, original_method)
    original_visibility = T::Private::Methods.visibility_method_name(mod, method_sig.method_name)
    if method_sig.mode == T::Private::Methods::Modes.abstract
      create_abstract_wrapper(mod, method_sig, original_method, original_visibility)
    # Do nothing in this case; this method was not wrapped in _on_method_added.
    elsif method_sig.defined_raw
    # Note, this logic is duplicated (intentionally, for micro-perf) at `Methods._on_method_added`,
    # make sure to keep changes in sync.
    # This is a trapdoor point for each method:
    # if a given method is wrapped, it stays wrapped; and if not, it's never wrapped.
    # (Therefore, we need the `@wrapped_tests_with_validation` check in `T::RuntimeLevels`.)
    elsif method_sig.check_level == :always || (method_sig.check_level == :tests && T::Private::RuntimeLevels.check_tests?)
      create_validator_method(mod, original_method, method_sig, original_visibility)
    else
      T::Configuration.without_ruby_warnings do
        # get all the shims out of the way and put back the original method
        T::Private::DeclState.current.without_on_method_added do
          T::Private::ClassUtils.def_with_visibility(mod, method_sig.method_name, original_visibility, original_method)
        end
      end
    end
    # Return the newly created method (or the original one if we didn't replace it)
    mod.instance_method(method_sig.method_name)
  end

  @is_allowed_to_have_fast_path = true
  def self.is_allowed_to_have_fast_path
    @is_allowed_to_have_fast_path
  end

  def self.disable_fast_path
    @is_allowed_to_have_fast_path = false
  end

  def self.create_abstract_wrapper(mod, method_sig, original_method, original_visibility)
    T::Configuration.without_ruby_warnings do
      T::Private::DeclState.current.without_on_method_added do
        mod.module_eval(<<~METHOD, __FILE__, __LINE__ + 1)
          #{original_visibility}

          def #{method_sig.method_name}(...)
            # We allow abstract methods to be implemented by things further down the ancestor chain.
            # So, if a super method exists, call it.
            if defined?(super)
              super
            else
              raise NotImplementedError.new(
                "The method `#{method_sig.method_name}` on #{mod} is declared as `abstract`. It does not have an implementation."
              )
            end
          end
        METHOD
      end
    end
  end

  def self.create_validator_method(mod, original_method, method_sig, original_visibility)
    has_fixed_arity = method_sig.kwarg_types.empty? && !method_sig.has_rest && !method_sig.has_keyrest &&
      original_method.parameters.all? { |(kind, _name)| kind == :req || kind == :block }
    can_skip_block_type = method_sig.block_type.nil? || method_sig.block_type.valid?(nil)
    ok_for_fast_path = has_fixed_arity && can_skip_block_type && !method_sig.bind && method_sig.arg_types.length < 5 && is_allowed_to_have_fast_path

    all_args_are_simple = ok_for_fast_path && method_sig.arg_types.all? { |_name, type| type.is_a?(T::Types::Simple) }
    simple_method = all_args_are_simple && method_sig.return_type.is_a?(T::Types::Simple)
    simple_procedure = all_args_are_simple && method_sig.return_type.is_a?(T::Private::Types::Void)

    # All the types for which valid? unconditionally returns `true`
    return_is_ignorable =
      method_sig.return_type.equal?(T::Types::Untyped::Private::INSTANCE) ||
      method_sig.return_type.equal?(T::Types::Anything::Private::INSTANCE) ||
      method_sig.return_type.equal?(T::Types::AttachedClassType::Private::INSTANCE) ||
      method_sig.return_type.equal?(T::Types::SelfType::Private::INSTANCE) ||
      method_sig.return_type.is_a?(T::Types::TypeParameter) ||
      method_sig.return_type.is_a?(T::Types::TypeVariable) ||
      (method_sig.return_type.is_a?(T::Types::Simple) && method_sig.return_type.raw_type.equal?(BasicObject))

    returns_anything_method = all_args_are_simple && return_is_ignorable

    T::Configuration.without_ruby_warnings do
      T::Private::DeclState.current.without_on_method_added do
        if simple_method
          create_validator_method_fast(mod, original_method, method_sig, original_visibility)
        elsif returns_anything_method
          create_validator_method_skip_return_fast(mod, original_method, method_sig, original_visibility)
        elsif simple_procedure
          create_validator_procedure_fast(mod, original_method, method_sig, original_visibility)
        elsif ok_for_fast_path && method_sig.return_type.is_a?(T::Private::Types::Void)
          create_validator_procedure_medium(mod, original_method, method_sig, original_visibility)
        elsif ok_for_fast_path && return_is_ignorable
          create_validator_method_skip_return_medium(mod, original_method, method_sig, original_visibility)
        elsif ok_for_fast_path
          create_validator_method_medium(mod, original_method, method_sig, original_visibility)
        elsif can_skip_block_type
          # The Ruby VM already validates that any block passed to a method
          # must be either `nil` or a `Proc` object, so there's no need to also
          # have sorbet-runtime check that.
          create_validator_slow_skip_block_type(mod, original_method, method_sig, original_visibility)
        else
          create_validator_slow(mod, original_method, method_sig, original_visibility)
        end
      end
      mod.send(original_visibility, method_sig.method_name)
    end
  end

  def self.create_validator_slow_skip_block_type(mod, original_method, method_sig, original_visibility)
    T::Private::ClassUtils.def_with_visibility(mod, method_sig.method_name, original_visibility) do |*args, &blk|
      CallValidation.validate_call_skip_block_type(self, original_method, method_sig, args, blk)
    end
  end

  def self.validate_call_skip_block_type(instance, original_method, method_sig, args, blk)
    # This method is called for every `sig`. It's critical to keep it fast and
    # reduce number of allocations that happen here.

    if method_sig.bind
      message = method_sig.bind.error_message_for_obj(instance)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Bind',
          nil,
          method_sig.bind,
          instance
        )
      end
    end

    # NOTE: We don't bother validating for missing or extra kwargs;
    # the method call itself will take care of that.
    method_sig.each_args_value_type(args) do |name, arg, type|
      message = type.error_message_for_obj(arg)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Parameter',
          name,
          type,
          arg,
          caller_offset: 2
        )
      end
    end

    # The original method definition allows passing `nil` for the `&blk`
    # argument, so we do not have to do any method_sig.block_type type checks
    # of our own.

    # The following line breaks are intentional to show nice pry message










    # PRY note:
    # this code is sig validation code.
    # Please issue `finish` to step out of it

    return_value = original_method.bind_call(instance, *args, &blk)

    # The only type that is allowed to change the return value is `.void`.
    # It ignores what you returned and changes it to be a private singleton.
    if method_sig.return_type.is_a?(T::Private::Types::Void)
      T::Private::Types::Void::VOID
    else
      message = method_sig.return_type.error_message_for_obj(return_value)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Return value',
          nil,
          method_sig.return_type,
          return_value,
        )
      end
      return_value
    end
  end

  def self.create_validator_slow(mod, original_method, method_sig, original_visibility)
    T::Private::ClassUtils.def_with_visibility(mod, method_sig.method_name, original_visibility) do |*args, &blk|
      CallValidation.validate_call(self, original_method, method_sig, args, blk)
    end
  end

  def self.validate_call(instance, original_method, method_sig, args, blk)
    # This method is called for every `sig`. It's critical to keep it fast and
    # reduce number of allocations that happen here.

    if method_sig.bind
      message = method_sig.bind.error_message_for_obj(instance)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Bind',
          nil,
          method_sig.bind,
          instance
        )
      end
    end

    # NOTE: We don't bother validating for missing or extra kwargs;
    # the method call itself will take care of that.
    method_sig.each_args_value_type(args) do |name, arg, type|
      message = type.error_message_for_obj(arg)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Parameter',
          name,
          type,
          arg,
          caller_offset: 2
        )
      end
    end

    # The Ruby VM already checks that `&blk` is either a `Proc` type or `nil`:
    # https://github.com/ruby/ruby/blob/v2_7_6/vm_args.c#L1150-L1154
    # And `T.proc` types don't (can't) do any runtime arg checking, so we can
    # save work by simply checking that `blk` is non-nil (if the method allows
    # `nil` for the block, it would not have used this validate_call path).
    unless blk
      # Have to use `&.` here, because it's technically a public API that
      # people can _always_ call `validate_call` to validate any signature
      # (i.e., the faster validators are merely optimizations).
      # In practice, this only affects the first call to the method (before the
      # optimized validators have a chance to replace the initial, slow
      # wrapper).
      message = method_sig.block_type&.error_message_for_obj(blk)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Block parameter',
          method_sig.block_name,
          method_sig.block_type,
          blk
        )
      end
    end

    # The following line breaks are intentional to show nice pry message










    # PRY note:
    # this code is sig validation code.
    # Please issue `finish` to step out of it

    return_value = original_method.bind_call(instance, *args, &blk)

    # The only type that is allowed to change the return value is `.void`.
    # It ignores what you returned and changes it to be a private singleton.
    if method_sig.return_type.is_a?(T::Private::Types::Void)
      T::Private::Types::Void::VOID
    else
      message = method_sig.return_type.error_message_for_obj(return_value)
      if message
        CallValidation.report_error(
          method_sig,
          message,
          'Return value',
          nil,
          method_sig.return_type,
          return_value,
        )
      end
      return_value
    end
  end

  def self.report_error(method_sig, error_message, kind, name, type, value, caller_offset: 0)
    caller_loc = T.must(caller_locations(3 + caller_offset, 1))[0]
    method = method_sig.method
    definition_file, definition_line = method.source_location

    owner = method.owner
    pretty_method_name =
      if owner.singleton_class? && owner.respond_to?(:attached_object)
        # attached_object is new in Ruby 3.2
        "#{owner.attached_object}.#{method.name}"
      else
        "#{owner}##{method.name}"
      end

    pretty_message = "#{kind}#{name ? " '#{name}'" : ''}: #{error_message}\n" \
      "Caller: #{caller_loc.path}:#{caller_loc.lineno}\n" \
      "Definition: #{definition_file}:#{definition_line} (#{pretty_method_name})"

    T::Configuration.call_validation_error_handler(
      method_sig,
      message: error_message,
      pretty_message: pretty_message,
      kind: kind,
      name: name,
      type: type,
      value: value,
      location: caller_loc
    )
  end
end

require_relative './call_validation_2_7'
