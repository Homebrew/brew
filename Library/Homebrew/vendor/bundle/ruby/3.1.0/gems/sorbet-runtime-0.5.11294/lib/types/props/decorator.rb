# frozen_string_literal: true
# typed: strict

# NB: This is not actually a decorator. It's just named that way for consistency
# with DocumentDecorator and ModelDecorator (which both seem to have been written
# with an incorrect understanding of the decorator pattern). These "decorators"
# should really just be static methods on private modules (we'd also want/need to
# replace decorator overrides in plugins with class methods that expose the necessary
# functionality).
class T::Props::Decorator
  extend T::Sig

  Rules = T.type_alias {T::Hash[Symbol, T.untyped]}
  DecoratedInstance = T.type_alias {Object} # Would be T::Props, but that produces circular reference errors in some circumstances
  PropType = T.type_alias {T::Types::Base}
  PropTypeOrClass = T.type_alias {T.any(PropType, Module)}

  class NoRulesError < StandardError; end

  EMPTY_PROPS = T.let({}.freeze, T::Hash[Symbol, Rules], checked: false)
  private_constant :EMPTY_PROPS

  sig {params(klass: T.untyped).void.checked(:never)}
  def initialize(klass)
    @class = T.let(klass, T.all(Module, T::Props::ClassMethods))
    @class.plugins.each do |mod|
      T::Props::Plugin::Private.apply_decorator_methods(mod, self)
    end
    @props = T.let(EMPTY_PROPS, T::Hash[Symbol, Rules], checked: false)
  end

  # checked(:never) - O(prop accesses)
  sig {returns(T::Hash[Symbol, Rules]).checked(:never)}
  attr_reader :props

  sig {returns(T::Array[Symbol])}
  def all_props
    props.keys
  end

  # checked(:never) - O(prop accesses)
  sig {params(prop: T.any(Symbol, String)).returns(Rules).checked(:never)}
  def prop_rules(prop)
    props[prop.to_sym] || raise("No such prop: #{prop.inspect}")
  end

  # checked(:never) - Rules hash is expensive to check
  sig {params(prop: Symbol, rules: Rules).void.checked(:never)}
  def add_prop_definition(prop, rules)
    override = rules.delete(:override)

    if props.include?(prop) && !override
      raise ArgumentError.new("Attempted to redefine prop #{prop.inspect} on class #{@class} that's already defined without specifying :override => true: #{prop_rules(prop)}")
    elsif !props.include?(prop) && override
      raise ArgumentError.new("Attempted to override a prop #{prop.inspect} on class #{@class} that doesn't already exist")
    end

    @props = @props.merge(prop => rules.freeze).freeze
  end

  # Heads up!
  #
  # There are already too many ad-hoc options on the prop DSL.
  #
  # We have already done a lot of work to remove unnecessary and confusing
  # options. If you're considering adding a new rule key, please come chat with
  # the Sorbet team first, as we'd really like to learn more about how to best
  # solve the problem you're encountering.
  VALID_RULE_KEYS = T.let(%i[
    enum
    foreign
    ifunset
    immutable
    override
    redaction
    sensitivity
    without_accessors
    clobber_existing_method!
    extra
    setter_validate
    _tnilable
  ].to_h {|k| [k, true]}.freeze, T::Hash[Symbol, T::Boolean], checked: false)
  private_constant :VALID_RULE_KEYS

  sig {params(key: Symbol).returns(T::Boolean).checked(:never)}
  def valid_rule_key?(key)
    !!VALID_RULE_KEYS[key]
  end

  # checked(:never) - O(prop accesses)
  sig {returns(T.all(Module, T::Props::ClassMethods)).checked(:never)}
  def decorated_class
    @class
  end

  # Accessors

  # Use this to validate that a value will validate for a given prop. Useful for knowing whether a value can be set on a model without setting it.
  #
  # checked(:never) - potentially O(prop accesses) depending on usage pattern
  sig {params(prop: Symbol, val: T.untyped).void.checked(:never)}
  def validate_prop_value(prop, val)
    prop_rules(prop).fetch(:value_validate_proc).call(val)
  end

  # For performance, don't use named params here.
  # Passing in rules here is purely a performance optimization.
  # Unlike the other methods that take rules, this one calls prop_rules for
  # the default, which raises if the prop doesn't exist (this maintains
  # preexisting behavior).
  #
  # Note this path is NOT used by generated setters on instances,
  # which are defined using `setter_proc` directly.
  #
  # checked(:never) - O(prop accesses)
  sig do
    params(
      instance: DecoratedInstance,
      prop: Symbol,
      val: T.untyped,
      rules: Rules
    )
    .void
    .checked(:never)
  end
  def prop_set(instance, prop, val, rules=prop_rules(prop))
    instance.instance_exec(val, &rules.fetch(:setter_proc))
  end
  alias_method :set, :prop_set

  # Only Models have any custom get logic but we need to call this on
  # non-Models since we don't know at code gen time what we have.
  sig do
    params(
      instance: DecoratedInstance,
      prop: Symbol,
      value: T.untyped
    )
    .returns(T.untyped)
    .checked(:never)
  end
  def prop_get_logic(instance, prop, value)
    value
  end

  # For performance, don't use named params here.
  # Passing in rules here is purely a performance optimization.
  #
  # Note this path is NOT used by generated getters on instances,
  # unless `ifunset` is used on the prop, or `prop_get` is overridden.
  #
  # checked(:never) - O(prop accesses)
  sig do
    params(
      instance: DecoratedInstance,
      prop: T.any(String, Symbol),
      rules: Rules
    )
    .returns(T.untyped)
    .checked(:never)
  end
  def prop_get(instance, prop, rules=prop_rules(prop))
    val = instance.instance_variable_get(rules[:accessor_key]) if instance.instance_variable_defined?(rules[:accessor_key])
    if !val.nil?
      val
    elsif (d = rules[:ifunset])
      T::Props::Utils.deep_clone_object(d)
    else
      nil
    end
  end

  sig do
    params(
      instance: DecoratedInstance,
      prop: T.any(String, Symbol),
      rules: Rules
    )
    .returns(T.untyped)
    .checked(:never)
  end
  def prop_get_if_set(instance, prop, rules=prop_rules(prop))
    instance.instance_variable_get(rules[:accessor_key]) if instance.instance_variable_defined?(rules[:accessor_key])
  end
  alias_method :get, :prop_get_if_set # Alias for backwards compatibility

  # checked(:never) - O(prop accesses)
  sig do
    params(
      instance: DecoratedInstance,
      prop: Symbol,
      foreign_class: Module,
      rules: Rules,
      opts: T::Hash[Symbol, T.untyped],
    )
    .returns(T.untyped)
    .checked(:never)
  end
  def foreign_prop_get(instance, prop, foreign_class, rules=prop_rules(prop), opts={})
    return if !(value = prop_get(instance, prop, rules))
    T.unsafe(foreign_class).load(value, {}, opts)
  end

  # TODO: we should really be checking all the methods on `cls`, not just Object
  BANNED_METHOD_NAMES = T.let(Object.instance_methods.each_with_object({}) {|x, acc| acc[x] = true}.freeze, T::Hash[Symbol, TrueClass], checked: false)

  # checked(:never) - Rules hash is expensive to check
  sig do
    params(
      name: Symbol,
      cls: Module,
      rules: Rules,
      type: PropTypeOrClass
    )
    .void
    .checked(:never)
  end
  def prop_validate_definition!(name, cls, rules, type)
    validate_prop_name(name)

    if rules.key?(:pii)
      raise ArgumentError.new("The 'pii:' option for props has been renamed " \
        "to 'sensitivity:' (in prop #{@class.name}.#{name})")
    end

    if rules.keys.any? {|k| !valid_rule_key?(k)}
      raise ArgumentError.new("At least one invalid prop arg supplied in #{self}: #{rules.keys.inspect}")
    end

    if !rules[:clobber_existing_method!] && !rules[:without_accessors] && BANNED_METHOD_NAMES.include?(name.to_sym)
      raise ArgumentError.new(
        "#{name} can't be used as a prop in #{@class} because a method with " \
        "that name already exists (defined by #{@class.instance_method(name).owner} " \
        "at #{@class.instance_method(name).source_location || '<unknown>'}). " \
        "(If using this name is unavoidable, try `without_accessors: true`.)"
      )
    end

    extra = rules[:extra]
    if !extra.nil? && !extra.is_a?(Hash)
      raise ArgumentError.new("Extra metadata must be a Hash in prop #{@class.name}.#{name}")
    end

    nil
  end

  SAFE_NAME = T.let(/\A[A-Za-z_][A-Za-z0-9_-]*\z/.freeze, Regexp, checked: false)

  # Used to validate both prop names and serialized forms
  sig {params(name: T.any(Symbol, String)).void.checked(:never)}
  private def validate_prop_name(name)
    if !name.match?(SAFE_NAME)
      raise ArgumentError.new("Invalid prop name in #{@class.name}: #{name}")
    end
  end

  # This converts the type from a T::Type to a regular old ruby class.
  sig {params(type: T::Types::Base).returns(Module).checked(:never)}
  private def convert_type_to_class(type)
    case type
    when T::Types::TypedArray, T::Types::FixedArray
      Array
    when T::Types::TypedHash, T::Types::FixedHash
      Hash
    when T::Types::TypedSet
      Set
    when T::Types::Union
      # The below unwraps our T.nilable types for T::Props if we can.
      # This lets us do things like specify: const T.nilable(String), foreign: Opus::DB::Model::Merchant
      non_nil_type = T::Utils.unwrap_nilable(type)
      if non_nil_type
        convert_type_to_class(non_nil_type)
      else
        Object
      end
    when T::Types::Simple
      type.raw_type
    else
      # This isn't allowed unless whitelisted_for_underspecification is
      # true, due to the check in prop_validate_definition
      Object
    end
  end

  # Returns `true` when the type of the prop is nilable, or the field is typed
  # as `T.untyped`, a `:default` is present in the rules hash, and its value is
  # `nil`. The latter case is a workaround for explicitly not supporting the use
  # of `T.nilable(T.untyped)`.
  #
  # checked(:never) - Rules hash is expensive to check
  sig do
    params(
      cls: PropTypeOrClass,
      rules: Rules,
    )
    .returns(T.anything)
    .checked(:never)
  end
  private def prop_nilable?(cls, rules)
    # NB: `prop` and `const` do not `T::Utils::coerce the type of the prop if it is a `Module`,
    # hence the bare `NilClass` check.
    T::Utils::Nilable.is_union_with_nilclass(cls) || ((cls == T.untyped || cls == NilClass) && rules.key?(:default) && rules[:default].nil?)
  end

  # checked(:never) - Rules hash is expensive to check
  sig do
    params(
      name: T.any(Symbol, String),
      cls: PropTypeOrClass,
      rules: Rules,
    )
    .void
    .checked(:never)
  end
  def prop_defined(name, cls, rules={})
    cls = T::Utils.resolve_alias(cls)

    if prop_nilable?(cls, rules)
      # :_tnilable is introduced internally for performance purpose so that clients do not need to call
      # T::Utils::Nilable.is_tnilable(cls) again.
      # It is strictly internal: clients should always use T::Props::Utils.required_prop?() or
      # T::Props::Utils.optional_prop?() for checking whether a field is required or optional.
      rules[:_tnilable] = true
    end

    name = name.to_sym
    type = cls
    if !cls.is_a?(Module)
      cls = convert_type_to_class(cls)
    end
    type_object = smart_coerce(type, enum: rules[:enum])

    prop_validate_definition!(name, cls, rules, type_object)

    # Retrieve the possible underlying object with T.nilable.
    type = T::Utils::Nilable.get_underlying_type(type)

    rules_sensitivity = rules[:sensitivity]
    sensitivity_and_pii = {sensitivity: rules_sensitivity}
    if !rules_sensitivity.nil?
      normalize = T::Configuration.normalize_sensitivity_and_pii_handler
      if normalize
        sensitivity_and_pii = normalize.call(sensitivity_and_pii)

        # We check for Class so this is only applied on concrete
        # documents/models; We allow mixins containing props to not
        # specify their PII nature, as long as every class into which they
        # are ultimately included does.
        #
        if sensitivity_and_pii[:pii] && @class.is_a?(Class) && !T.unsafe(@class).contains_pii?
          raise ArgumentError.new(
            'Cannot include a pii prop in a class that declares `contains_no_pii`'
          )
        end
      end
    end

    rules[:type] = type
    rules[:type_object] = type_object
    rules[:accessor_key] = "@#{name}".to_sym
    rules[:sensitivity] = sensitivity_and_pii[:sensitivity]
    rules[:pii] = sensitivity_and_pii[:pii]
    rules[:extra] = rules[:extra]&.freeze

    # extra arbitrary metadata attached by the code defining this property

    validate_not_missing_sensitivity(name, rules)

    # for backcompat (the `:array` key is deprecated but because the name is
    # so generic it's really hard to be sure it's not being relied on anymore)
    if type.is_a?(T::Types::TypedArray)
      inner = T::Utils::Nilable.get_underlying_type(type.type)
      if inner.is_a?(Module)
        rules[:array] = inner
      end
    end

    setter_proc, value_validate_proc = T::Props::Private::SetterFactory.build_setter_proc(@class, name, rules)
    setter_proc.freeze
    value_validate_proc.freeze
    rules[:setter_proc] = setter_proc
    rules[:value_validate_proc] = value_validate_proc

    add_prop_definition(name, rules)

    # NB: using `without_accessors` doesn't make much sense unless you also define some other way to
    # get at the property (e.g., Chalk::ODM::Document exposes `get` and `set`).
    define_getter_and_setter(name, rules) unless rules[:without_accessors]

    handle_foreign_option(name, cls, rules, rules[:foreign]) if rules[:foreign]
    handle_redaction_option(name, rules[:redaction]) if rules[:redaction]
  end

  # checked(:never) - Rules hash is expensive to check
  sig {params(name: Symbol, rules: Rules).void.checked(:never)}
  private def define_getter_and_setter(name, rules)
    T::Configuration.without_ruby_warnings do
      if !rules[:immutable]
        if method(:prop_set).owner != T::Props::Decorator
          @class.send(:define_method, "#{name}=") do |val|
            T.unsafe(self.class).decorator.prop_set(self, name, val, rules)
          end
        else
          # Fast path (~4x faster as of Ruby 2.6)
          @class.send(:define_method, "#{name}=", &rules.fetch(:setter_proc))
        end
      end

      if method(:prop_get).owner != T::Props::Decorator || rules.key?(:ifunset)
        @class.send(:define_method, name) do
          T.unsafe(self.class).decorator.prop_get(self, name, rules)
        end
      else
        # Fast path (~30x faster as of Ruby 2.6)
        @class.send(:attr_reader, name) # send is used because `attr_reader` is private in 2.4
      end
    end
  end

  sig do
    params(type: PropTypeOrClass, enum: T.untyped)
    .returns(T::Types::Base)
    .checked(:never)
  end
  private def smart_coerce(type, enum:)
    # Backwards compatibility for pre-T::Types style
    type = T::Utils.coerce(type)
    if enum.nil?
      type
    else
      nonnil_type = T::Utils.unwrap_nilable(type)
      if nonnil_type
        T.unsafe(T.nilable(T.all(nonnil_type, T.deprecated_enum(enum))))
      else
        T.unsafe(T.all(T.unsafe(type), T.deprecated_enum(enum)))
      end
    end
  end

  # checked(:never) - Rules hash is expensive to check
  sig {params(prop_name: Symbol, rules: Rules).void.checked(:never)}
  private def validate_not_missing_sensitivity(prop_name, rules)
    if rules[:sensitivity].nil?
      if rules[:redaction]
        T::Configuration.hard_assert_handler(
          "#{@class}##{prop_name} has a 'redaction:' annotation but no " \
          "'sensitivity:' annotation. This is probably wrong, because if a " \
          "prop needs redaction then it is probably sensitive. Add a " \
          "sensitivity annotation like 'sensitivity: Opus::Sensitivity::PII." \
          "whatever', or explicitly override this check with 'sensitivity: []'."
        )
      end
      # TODO(PRIVACYENG-982) Ideally we'd also check for 'password' and possibly
      # other terms, but this interacts badly with ProtoDefinedDocument because
      # the proto syntax currently can't declare "sensitivity: []"
      if /\bsecret\b/.match?(prop_name)
        T::Configuration.hard_assert_handler(
          "#{@class}##{prop_name} has the word 'secret' in its name, but no " \
          "'sensitivity:' annotation. This is probably wrong, because if a " \
          "prop is named 'secret' then it is probably sensitive. Add a " \
          "sensitivity annotation like 'sensitivity: Opus::Sensitivity::NonPII." \
          "security_token', or explicitly override this check with " \
          "'sensitivity: []'."
        )
      end
    end
  end

  # Create `#{prop_name}_redacted` method
  sig do
    params(
      prop_name: Symbol,
      redaction: T.untyped,
    )
    .void
    .checked(:never)
  end
  private def handle_redaction_option(prop_name, redaction)
    redacted_method = "#{prop_name}_redacted"

    @class.send(:define_method, redacted_method) do
      value = self.public_send(prop_name)
      handler = T::Configuration.redaction_handler
      if !handler
        raise "Using `redaction:` on a prop requires specifying `T::Configuration.redaction_handler`"
      end
      handler.call(value, redaction)
    end
  end

  sig do
    params(
      option_sym: Symbol,
      foreign: T.untyped,
      valid_type_msg: String,
    )
    .void
    .checked(:never)
  end
  private def validate_foreign_option(option_sym, foreign, valid_type_msg:)
    if foreign.is_a?(Symbol) || foreign.is_a?(String)
      raise ArgumentError.new(
        "Using a symbol/string for `#{option_sym}` is no longer supported. Instead, use a Proc " \
        "that returns the class, e.g., foreign: -> {Foo}"
      )
    end

    if !foreign.is_a?(Proc) && !foreign.is_a?(Array) && !foreign.respond_to?(:load)
      raise ArgumentError.new("The `#{option_sym}` option must be #{valid_type_msg}")
    end
  end

  # checked(:never) - Rules hash is expensive to check
  sig do
    params(
      prop_name: T.any(String, Symbol),
      rules: Rules,
      foreign: T.untyped,
    )
    .void
    .checked(:never)
  end
  private def define_foreign_method(prop_name, rules, foreign)
    fk_method = "#{prop_name}_"

    # n.b. there's no clear reason *not* to allow additional options
    # here, but we're baking in `allow_direct_mutation` since we
    # *haven't* allowed additional options in the past and want to
    # default to keeping this interface narrow.
    foreign = T.let(foreign, T.untyped, checked: false)
    @class.send(:define_method, fk_method) do |allow_direct_mutation: nil|
      if foreign.is_a?(Proc)
        resolved_foreign = foreign.call
        if !resolved_foreign.respond_to?(:load)
          raise ArgumentError.new(
            "The `foreign` proc for `#{prop_name}` must return a model class. " \
            "Got `#{resolved_foreign.inspect}` instead."
          )
        end
        # `foreign` is part of the closure state, so this will persist to future invocations
        # of the method, optimizing it so this only runs on the first invocation.
        foreign = resolved_foreign
      end
      opts = if allow_direct_mutation.nil?
        {}
      else
        {allow_direct_mutation: allow_direct_mutation}
      end

      T.unsafe(self.class).decorator.foreign_prop_get(self, prop_name, foreign, rules, opts)
    end

    force_fk_method = "#{fk_method}!"
    @class.send(:define_method, force_fk_method) do |allow_direct_mutation: nil|
      loaded_foreign = send(fk_method, allow_direct_mutation: allow_direct_mutation)
      if !loaded_foreign
        T::Configuration.hard_assert_handler(
          'Failed to load foreign model',
          storytime: {method: force_fk_method, class: self.class}
        )
      end
      loaded_foreign
    end
  end

  # checked(:never) - Rules hash is expensive to check
  sig do
    params(
      prop_name: Symbol,
      prop_cls: Module,
      rules: Rules,
      foreign: T.untyped,
    )
    .void
    .checked(:never)
  end
  private def handle_foreign_option(prop_name, prop_cls, rules, foreign)
    validate_foreign_option(
      :foreign, foreign, valid_type_msg: "a model class or a Proc that returns one"
    )

    if prop_cls != String
      raise ArgumentError.new("`foreign` can only be used with a prop type of String")
    end

    if foreign.is_a?(Array)
      # We don't support arrays with `foreign` because it's hard to both preserve ordering and
      # keep them from being lurky performance hits by issuing a bunch of un-batched DB queries.
      # We could potentially address that by porting over something like AmbiguousIDLoader.
      raise ArgumentError.new(
        "Using an array for `foreign` is no longer supported. Instead, please use a union type of " \
        "token types for the prop type, e.g., T.any(Opus::Autogen::Tokens::FooModelToken, Opus::Autogen::Tokens::BarModelToken)"
      )
    end

    unless foreign.is_a?(Proc)
      T::Configuration.soft_assert_handler(<<~MESSAGE, storytime: {prop: prop_name, value: foreign}, notify: 'jerry')
        Please use a Proc that returns a model class instead of the model class itself as the argument to `foreign`. In other words:

          instead of `prop :foo, String, foreign: FooModel`
          use `prop :foo, String, foreign: -> {FooModel}`

      MESSAGE
    end

    define_foreign_method(prop_name, rules, foreign)
  end

  # TODO: rename this to props_inherited
  #
  # This gets called when a module or class that extends T::Props gets included, extended,
  # prepended, or inherited.
  sig {params(child: Module).void.checked(:never)}
  def model_inherited(child)
    child.extend(T::Props::ClassMethods)
    child = T.cast(child, T.all(Module, T::Props::ClassMethods))

    child.plugins.concat(decorated_class.plugins)
    decorated_class.plugins.each do |mod|
      # NB: apply_class_methods must not be an instance method on the decorator itself,
      # otherwise we'd have to call child.decorator here, which would create the decorator
      # before any `decorator_class` override has a chance to take effect (see the comment below).
      T::Props::Plugin::Private.apply_class_methods(mod, child)
    end

    props.each do |name, rules|
      copied_rules = rules.dup
      # NB: Calling `child.decorator` here is a timb bomb that's going to give someone a really bad
      # time. Any class that defines props and also overrides the `decorator_class` method is going
      # to reach this line before its override take effect, turning it into a no-op.
      child.decorator.add_prop_definition(name, copied_rules)

      # It's a bit tricky to support `prop_get` hooks added by plugins without
      # sacrificing the `attr_reader` fast path or clobbering customized getters
      # defined manually on a child.
      #
      # To make this work, we _do_ clobber getters defined on the child, but only if:
      # (a) it's needed in order to support a `prop_get` hook, and
      # (b) it's safe because the getter was defined by this file.
      #
      unless rules[:without_accessors]
        if clobber_getter?(child, name)
          child.send(:define_method, name) do
            T.unsafe(self.class).decorator.prop_get(self, name, rules)
          end
        end

        if !rules[:immutable] && clobber_setter?(child, name)
          child.send(:define_method, "#{name}=") do |val|
            T.unsafe(self.class).decorator.prop_set(self, name, val, rules)
          end
        end
      end
    end
  end

  sig {params(child: T.all(Module, T::Props::ClassMethods), prop: Symbol).returns(T::Boolean).checked(:never)}
  private def clobber_getter?(child, prop)
    !!(child.decorator.method(:prop_get).owner != method(:prop_get).owner &&
       child.instance_method(prop).source_location&.first == __FILE__)
  end

  sig {params(child: T.all(Module, T::Props::ClassMethods), prop: Symbol).returns(T::Boolean).checked(:never)}
  private def clobber_setter?(child, prop)
    !!(child.decorator.method(:prop_set).owner != method(:prop_set).owner &&
       child.instance_method("#{prop}=").source_location&.first == __FILE__)
  end

  sig {params(mod: Module).void.checked(:never)}
  def plugin(mod)
    decorated_class.plugins << mod
    T::Props::Plugin::Private.apply_class_methods(mod, decorated_class)
    T::Props::Plugin::Private.apply_decorator_methods(mod, self)
  end
end
