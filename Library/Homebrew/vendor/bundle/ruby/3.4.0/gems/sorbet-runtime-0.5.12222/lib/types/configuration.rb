# typed: true
# frozen_string_literal: true

module T::Configuration
  # Cache this comparisonn to avoid two allocations all over the place.
  AT_LEAST_RUBY_2_7 = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')

  # Announces to Sorbet that we are currently in a test environment, so it
  # should treat any sigs which are marked `.checked(:tests)` as if they were
  # just a normal sig.
  #
  # If this method is not called, sigs marked `.checked(:tests)` will not be
  # checked. In fact, such methods won't even be wrapped--the runtime will put
  # back the original method.
  #
  # Note: Due to the way sigs are evaluated and methods are wrapped, this
  # method MUST be called before any code calls `sig`. This method raises if
  # it has been called too late.
  def self.enable_checking_for_sigs_marked_checked_tests
    T::Private::RuntimeLevels.enable_checking_in_tests
  end

  # Announce to Sorbet that we would like the final checks to be enabled when
  # including and extending modules. Iff this is not called, then the following
  # example will not raise an error.
  #
  # ```ruby
  # module M
  #   extend T::Sig
  #   sig(:final) {void}
  #   def foo; end
  # end
  # class C
  #   include M
  #   def foo; end
  # end
  # ```
  def self.enable_final_checks_on_hooks
    T::Private::Methods.set_final_checks_on_hooks(true)
  end

  # Undo the effects of a previous call to
  # `enable_final_checks_on_hooks`.
  def self.reset_final_checks_on_hooks
    T::Private::Methods.set_final_checks_on_hooks(false)
  end

  @include_value_in_type_errors = true
  # Whether to include values in TypeError messages.
  #
  # Including values is useful for debugging, but can potentially leak
  # sensitive information to logs.
  #
  # @return [T::Boolean]
  def self.include_value_in_type_errors?
    @include_value_in_type_errors
  end

  # Configure if type errors excludes the value of the problematic type.
  #
  # The default is to include values in type errors:
  #   TypeError: Expected type Integer, got String with value "foo"
  #
  # When values are excluded from type errors:
  #   TypeError: Expected type Integer, got String
  def self.exclude_value_in_type_errors
    @include_value_in_type_errors = false
  end

  # Opposite of exclude_value_in_type_errors.
  # (Including values in type errors is the default)
  def self.include_value_in_type_errors
    @include_value_in_type_errors = true
  end

  # Whether VM-defined prop serialization/deserialization routines can be enabled.
  #
  # @return [T::Boolean]
  def self.can_enable_vm_prop_serde?
    T::Props::Private::DeserializerGenerator.respond_to?(:generate2)
  end

  @use_vm_prop_serde = false
  # Whether to use VM-defined prop serialization/deserialization routines.
  #
  # The default is to use runtime codegen inside sorbet-runtime itself.
  #
  # @return [T::Boolean]
  def self.use_vm_prop_serde?
    @use_vm_prop_serde || false
  end

  # Enable using VM-defined prop serialization/deserialization routines.
  #
  # This method is likely to break things outside of Stripe's systems.
  def self.enable_vm_prop_serde
    if !can_enable_vm_prop_serde?
      hard_assert_handler('Ruby VM is not setup to use VM-defined prop serde')
    end
    @use_vm_prop_serde = true
  end

  # Disable using VM-defined prop serialization/deserialization routines.
  def self.disable_vm_prop_serde
    @use_vm_prop_serde = false
  end

  # Configure the default checked level for a sig with no explicit `.checked`
  # builder. When unset, the default checked level is `:always`.
  #
  # Note: setting this option is potentially dangerous! Sorbet can't check all
  # code statically. The runtime checks complement the checks that Sorbet does
  # statically, so that methods don't have to guard themselves from being
  # called incorrectly by untyped code.
  #
  # @param [:never, :tests, :always] default_checked_level
  def self.default_checked_level=(default_checked_level)
    T::Private::RuntimeLevels.default_checked_level = default_checked_level
  end

  @inline_type_error_handler = nil
  # Set a handler to handle `TypeError`s raised by any in-line type assertions,
  # including `T.must`, `T.let`, `T.cast`, and `T.assert_type!`.
  #
  # By default, any `TypeError`s detected by this gem will be raised. Setting
  # inline_type_error_handler to an object that implements :call (e.g. proc or
  # lambda) allows users to customize the behavior when a `TypeError` is
  # raised on any inline type assertion.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error (pass
  #   nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [TypeError] error TypeError that was raised
  #  @param [Hash] opts A hash containing contextual information on the error:
  #  @option opts [String] :kind One of:
  #    ['T.cast', 'T.let', 'T.bind', 'T.assert_type!', 'T.must', 'T.absurd']
  #  @option opts [Object, nil] :type Expected param/return value type
  #  @option opts [Object] :value Actual param/return value
  #
  # @example
  #   T::Configuration.inline_type_error_handler = lambda do |error, opts|
  #     puts error.message
  #   end
  def self.inline_type_error_handler=(value)
    validate_lambda_given!(value)
    @inline_type_error_handler = value
  end

  private_class_method def self.inline_type_error_handler_default(error, opts)
    raise error
  end

  def self.inline_type_error_handler(error, opts={})
    if @inline_type_error_handler
      # Backwards compatibility before `inline_type_error_handler` took a second arg
      if @inline_type_error_handler.arity == 1
        @inline_type_error_handler.call(error)
      else
        @inline_type_error_handler.call(error, opts)
      end
    else
      inline_type_error_handler_default(error, opts)
    end
    nil
  end

  @sig_builder_error_handler = nil
  # Set a handler to handle errors that occur when the builder methods in the
  # body of a sig are executed. The sig builder methods are inside a proc so
  # that they can be lazily evaluated the first time the method being sig'd is
  # called.
  #
  # By default, improper use of the builder methods within the body of a sig
  # cause an ArgumentError to be raised. Setting sig_builder_error_handler to an
  # object that implements :call (e.g. proc or lambda) allows users to
  # customize the behavior when a sig can't be built for some reason.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error (pass
  #   nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [StandardError] error The error that was raised
  #  @param [Thread::Backtrace::Location] location Location of the error
  #
  # @example
  #   T::Configuration.sig_builder_error_handler = lambda do |error, location|
  #     puts error.message
  #   end
  def self.sig_builder_error_handler=(value)
    validate_lambda_given!(value)
    @sig_builder_error_handler = value
  end

  private_class_method def self.sig_builder_error_handler_default(error, location)
    raise ArgumentError.new("#{location.path}:#{location.lineno}: Error interpreting `sig`:\n  #{error.message}\n\n")
  end

  def self.sig_builder_error_handler(error, location)
    if @sig_builder_error_handler
      @sig_builder_error_handler.call(error, location)
    else
      sig_builder_error_handler_default(error, location)
    end
    nil
  end

  @sig_validation_error_handler = nil
  # Set a handler to handle sig validation errors.
  #
  # Sig validation errors include things like abstract checks, override checks,
  # and type compatibility of arguments. They happen after a sig has been
  # successfully built, but the built sig is incompatible with other sigs in
  # some way.
  #
  # By default, sig validation errors cause an exception to be raised.
  # Setting sig_validation_error_handler to an object that implements :call
  # (e.g. proc or lambda) allows users to customize the behavior when a method
  # signature's build fails.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error (pass
  #   nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [StandardError] error The error that was raised
  #  @param [Hash] opts A hash containing contextual information on the error:
  #  @option opts [Method, UnboundMethod] :method Method on which the signature build failed
  #  @option opts [T::Private::Methods::Declaration] :declaration Method
  #    signature declaration struct
  #  @option opts [T::Private::Methods::Signature, nil] :signature Signature
  #    that failed (nil if sig build failed before Signature initialization)
  #  @option opts [T::Private::Methods::Signature, nil] :super_signature Super
  #    method's signature (nil if method is not an override or super method
  #    does not have a method signature)
  #
  # @example
  #   T::Configuration.sig_validation_error_handler = lambda do |error, opts|
  #     puts error.message
  #   end
  def self.sig_validation_error_handler=(value)
    validate_lambda_given!(value)
    @sig_validation_error_handler = value
  end

  private_class_method def self.sig_validation_error_handler_default(error, opts)
    raise error
  end

  def self.sig_validation_error_handler(error, opts={})
    if @sig_validation_error_handler
      @sig_validation_error_handler.call(error, opts)
    else
      sig_validation_error_handler_default(error, opts)
    end
    nil
  end

  @call_validation_error_handler = nil
  # Set a handler for type errors that result from calling a method.
  #
  # By default, errors from calling a method cause an exception to be raised.
  # Setting call_validation_error_handler to an object that implements :call
  # (e.g. proc or lambda) allows users to customize the behavior when a method
  # is called with invalid parameters, or returns an invalid value.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error
  #   report (pass nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [T::Private::Methods::Signature] signature Signature that failed
  #  @param [Hash] opts A hash containing contextual information on the error:
  #  @option opts [String] :message Error message
  #  @option opts [String] :kind One of:
  #    ['Parameter', 'Block parameter', 'Return value']
  #  @option opts [Symbol] :name Param or block param name (nil for return
  #    value)
  #  @option opts [Object] :type Expected param/return value type
  #  @option opts [Object] :value Actual param/return value
  #  @option opts [Thread::Backtrace::Location] :location Location of the
  #    caller
  #
  # @example
  #   T::Configuration.call_validation_error_handler = lambda do |signature, opts|
  #     puts opts[:message]
  #   end
  def self.call_validation_error_handler=(value)
    validate_lambda_given!(value)
    @call_validation_error_handler = value
  end

  private_class_method def self.call_validation_error_handler_default(signature, opts)
    raise TypeError.new(opts[:pretty_message])
  end

  def self.call_validation_error_handler(signature, opts={})
    if @call_validation_error_handler
      @call_validation_error_handler.call(signature, opts)
    else
      call_validation_error_handler_default(signature, opts)
    end
    nil
  end

  @log_info_handler = nil
  # Set a handler for logging
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error
  #   report (pass nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [String] str Message to be logged
  #  @param [Hash] extra A hash containing additional parameters to be passed along to the logger.
  #
  # @example
  #   T::Configuration.log_info_handler = lambda do |str, extra|
  #     puts "#{str}, context: #{extra}"
  #   end
  def self.log_info_handler=(value)
    validate_lambda_given!(value)
    @log_info_handler = value
  end

  private_class_method def self.log_info_handler_default(str, extra)
    puts "#{str}, extra: #{extra}"
  end

  def self.log_info_handler(str, extra)
    if @log_info_handler
      @log_info_handler.call(str, extra)
    else
      log_info_handler_default(str, extra)
    end
  end

  @soft_assert_handler = nil
  # Set a handler for soft assertions
  #
  # These generally shouldn't stop execution of the program, but rather inform
  # some party of the assertion to action on later.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error
  #   report (pass nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [String] str Assertion message
  #  @param [Hash] extra A hash containing additional parameters to be passed along to the handler.
  #
  # @example
  #   T::Configuration.soft_assert_handler = lambda do |str, extra|
  #     puts "#{str}, context: #{extra}"
  #   end
  def self.soft_assert_handler=(value)
    validate_lambda_given!(value)
    @soft_assert_handler = value
  end

  private_class_method def self.soft_assert_handler_default(str, extra)
    puts "#{str}, extra: #{extra}"
  end

  def self.soft_assert_handler(str, extra)
    if @soft_assert_handler
      @soft_assert_handler.call(str, extra)
    else
      soft_assert_handler_default(str, extra)
    end
  end

  @hard_assert_handler = nil
  # Set a handler for hard assertions
  #
  # These generally should stop execution of the program, and optionally inform
  # some party of the assertion.
  #
  # @param [Lambda, Proc, Object, nil] value Proc that handles the error
  #   report (pass nil to reset to default behavior)
  #
  # Parameters passed to value.call:
  #
  #  @param [String] str Assertion message
  #  @param [Hash] extra A hash containing additional parameters to be passed along to the handler.
  #
  # @example
  #   T::Configuration.hard_assert_handler = lambda do |str, extra|
  #     raise "#{str}, context: #{extra}"
  #   end
  def self.hard_assert_handler=(value)
    validate_lambda_given!(value)
    @hard_assert_handler = value
  end

  private_class_method def self.hard_assert_handler_default(str, _)
    raise str
  end

  def self.hard_assert_handler(str, extra={})
    if @hard_assert_handler
      @hard_assert_handler.call(str, extra)
    else
      hard_assert_handler_default(str, extra)
    end
  end

  @scalar_types = nil
  # Set a list of class strings that are to be considered scalar.
  #   (pass nil to reset to default behavior)
  #
  # @param [String] values Class name.
  #
  # @example
  #   T::Configuration.scalar_types = ["NilClass", "TrueClass", "FalseClass", ...]
  def self.scalar_types=(values)
    if values.nil?
      @scalar_types = values
    else
      bad_values = values.reject { |v| v.class == String }
      unless bad_values.empty?
        raise ArgumentError.new("Provided values must all be class name strings.")
      end

      @scalar_types = values.each_with_object({}) { |x, acc| acc[x] = true }.freeze
    end
  end

  @default_scalar_types = {
    "NilClass" => true,
    "TrueClass" => true,
    "FalseClass" => true,
    "Integer" => true,
    "Float" => true,
    "String" => true,
    "Symbol" => true,
    "Time" => true,
    "T::Enum" => true,
  }.freeze

  def self.scalar_types
    @scalar_types || @default_scalar_types
  end

  # Guard against overrides of `name` or `to_s`
  MODULE_NAME = Module.instance_method(:name)
  private_constant :MODULE_NAME

  @default_module_name_mangler = if T::Configuration::AT_LEAST_RUBY_2_7
    ->(type) { MODULE_NAME.bind_call(type) }
  else
    ->(type) { MODULE_NAME.bind(type).call } # rubocop:disable Performance/BindCall
  end

  @module_name_mangler = nil

  def self.module_name_mangler
    @module_name_mangler || @default_module_name_mangler
  end

  # Set to override the default behavior for converting types
  #   to names in generated code. Used by the runtime implementation
  #   associated with `--stripe-packages` mode.
  #
  # @param [Lambda, Proc, nil] handler Proc that converts a type (Class/Module)
  #   to a String (pass nil to reset to default behavior)
  def self.module_name_mangler=(handler)
    @module_name_mangler = handler
  end

  @sensitivity_and_pii_handler = nil
  # Set to a PII handler function. This will be called with the `sensitivity:`
  # annotations on things that use `T::Props` and can modify them ahead-of-time.
  #
  # @param [Lambda, Proc, nil] handler Proc that takes a hash mapping symbols to the
  # prop values. Pass nil to avoid changing `sensitivity:` annotations.
  def self.normalize_sensitivity_and_pii_handler=(handler)
    @sensitivity_and_pii_handler = handler
  end

  def self.normalize_sensitivity_and_pii_handler
    @sensitivity_and_pii_handler
  end

  @redaction_handler = nil
  # Set to a redaction handling function. This will be called when the
  # `_redacted` version of a prop reader is used. By default this is set to
  # `nil` and will raise an exception when the redacted version of a prop is
  # accessed.
  #
  # @param [Lambda, Proc, nil] handler Proc that converts a value into its
  # redacted version according to the spec passed as the second argument.
  def self.redaction_handler=(handler)
    @redaction_handler = handler
  end

  def self.redaction_handler
    @redaction_handler
  end

  @class_owner_finder = nil
  # Set to a function which can get the 'owner' of a class. This is
  # used in reporting deserialization errors
  #
  # @param [Lambda, Proc, nil] handler Proc that takes a class and
  # produces its owner, or `nil` if it does not have one.
  def self.class_owner_finder=(handler)
    @class_owner_finder = handler
  end

  def self.class_owner_finder
    @class_owner_finder
  end

  # Temporarily disable ruby warnings while executing the given block. This is
  # useful when doing something that would normally cause a warning to be
  # emitted in Ruby verbose mode ($VERBOSE = true).
  #
  # @yield
  #
  def self.without_ruby_warnings
    if $VERBOSE
      begin
        original_verbose = $VERBOSE
        $VERBOSE = false
        yield
      ensure
        $VERBOSE = original_verbose
      end
    else
      yield
    end
  end

  @legacy_t_enum_migration_mode = false
  def self.enable_legacy_t_enum_migration_mode
    T::Enum.include(T::Enum::LegacyMigrationMode)
    @legacy_t_enum_migration_mode = true
  end
  def self.disable_legacy_t_enum_migration_mode
    @legacy_t_enum_migration_mode = false
  end
  def self.legacy_t_enum_migration_mode?
    @legacy_t_enum_migration_mode || false
  end

  @prop_freeze_handler = ->(instance, prop_name) {}

  def self.prop_freeze_handler=(handler)
    @prop_freeze_handler = handler
  end

  def self.prop_freeze_handler
    @prop_freeze_handler
  end

  @sealed_violation_whitelist = nil
  # @param [Array] sealed_violation_whitelist An array of Regexp to validate
  #   whether inheriting /including a sealed module outside the defining module
  #   should be allowed. Useful to whitelist benign violations, like shim files
  #   generated for an autoloader.
  def self.sealed_violation_whitelist=(sealed_violation_whitelist)
    if !@sealed_violation_whitelist.nil?
      raise ArgumentError.new("Cannot overwrite sealed_violation_whitelist after setting it")
    end

    case sealed_violation_whitelist
    when Array
      sealed_violation_whitelist.each do |x|
        case x
        when Regexp then nil
        else raise TypeError.new("sealed_violation_whitelist accepts an Array of Regexp")
        end
      end
    else
      raise TypeError.new("sealed_violation_whitelist= accepts an Array of Regexp")
    end

    @sealed_violation_whitelist = sealed_violation_whitelist
  end
  def self.sealed_violation_whitelist
    @sealed_violation_whitelist
  end

  private_class_method def self.validate_lambda_given!(value)
    if !value.nil? && !value.respond_to?(:call)
      raise ArgumentError.new("Provided value must respond to :call")
    end
  end
end
