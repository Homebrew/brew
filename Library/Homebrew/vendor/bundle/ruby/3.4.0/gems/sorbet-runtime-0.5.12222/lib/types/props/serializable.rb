# frozen_string_literal: true
# typed: false

module T::Props::Serializable
  include T::Props::Plugin
  # Required because we have special handling for `optional: false`
  include T::Props::Optional
  # Required because we have special handling for extra_props
  include T::Props::PrettyPrintable

  # Serializes this object to a hash, suitable for conversion to
  # JSON/BSON.
  #
  # @param strict [T::Boolean] (true) If false, do not raise an
  #   exception if this object has mandatory props with missing
  #   values.
  # @return [Hash] A serialization of this object.
  def serialize(strict=true)
    begin
      h = __t_props_generated_serialize(strict)
    rescue => e
      msg = self.class.decorator.message_with_generated_source_context(
        e,
        :__t_props_generated_serialize,
        :generate_serialize_source
      )
      if msg
        begin
          raise e.class.new(msg)
        rescue ArgumentError
          raise TypeError.new(msg)
        end
      else
        raise
      end
    end

    h.merge!(@_extra_props) if defined?(@_extra_props)
    h
  end

  private def __t_props_generated_serialize(strict)
    # No-op; will be overridden if there are any props.
    #
    # To see the definition for class `Foo`, run `Foo.decorator.send(:generate_serialize_source)`
    {}
  end

  # Populates the property values on this object with the values
  # from a hash. In general, prefer to use {.from_hash} to construct
  # a new instance, instead of loading into an existing instance.
  #
  # @param hash [Hash<String, Object>] The hash to take property
  #  values from.
  # @param strict [T::Boolean] (false) If true, raise an exception if
  #  the hash contains keys that do not correspond to any known
  #  props on this instance.
  # @return [void]
  def deserialize(hash, strict=false)
    begin
      hash_keys_matching_props = __t_props_generated_deserialize(hash)
    rescue => e
      msg = self.class.decorator.message_with_generated_source_context(
        e,
        :__t_props_generated_deserialize,
        :generate_deserialize_source
      )
      if msg
        begin
          raise e.class.new(msg)
        rescue ArgumentError
          raise TypeError.new(msg)
        end
      else
        raise
      end
    end

    if hash.size > hash_keys_matching_props
      serialized_forms = self.class.decorator.prop_by_serialized_forms
      extra = hash.reject { |k, _| serialized_forms.key?(k) }

      # `extra` could still be empty here if the input matches a `dont_store` prop;
      # historically, we just ignore those
      if !extra.empty?
        if strict
          raise "Unknown properties for #{self.class.name}: #{extra.keys.inspect}"
        else
          @_extra_props = extra
        end
      end
    end
  end

  private def __t_props_generated_deserialize(hash)
    # No-op; will be overridden if there are any props.
    #
    # To see the definition for class `Foo`, run `Foo.decorator.send(:generate_deserialize_source)`
    0
  end

  # with() will clone the old object to the new object and merge the specified props to the new object.
  def with(changed_props)
    with_existing_hash(changed_props, existing_hash: self.serialize)
  end

  private def recursive_stringify_keys(obj)
    if obj.is_a?(Hash)
      new_obj = obj.class.new
      obj.each do |k, v|
        new_obj[k.to_s] = recursive_stringify_keys(v)
      end
    elsif obj.is_a?(Array)
      new_obj = obj.map { |v| recursive_stringify_keys(v) }
    else
      new_obj = obj
    end
    new_obj
  end

  private def with_existing_hash(changed_props, existing_hash:)
    serialized = existing_hash
    new_val = self.class.from_hash(serialized.merge(recursive_stringify_keys(changed_props)))
    old_extra = self.instance_variable_get(:@_extra_props) if self.instance_variable_defined?(:@_extra_props)
    new_extra = new_val.instance_variable_get(:@_extra_props) if new_val.instance_variable_defined?(:@_extra_props)
    if old_extra != new_extra
      difference =
        if old_extra
          new_extra.reject { |k, v| old_extra[k] == v }
        else
          new_extra
        end
      raise ArgumentError.new("Unexpected arguments: input(#{changed_props}), unexpected(#{difference})")
    end
    new_val
  end

  # Asserts if this property is missing during strict serialize
  private def required_prop_missing_from_serialize(prop)
    if defined?(@_required_props_missing_from_deserialize) &&
       @_required_props_missing_from_deserialize&.include?(prop)
      # If the prop was already missing during deserialization, that means the application
      # code already had to deal with a nil value, which means we wouldn't be accomplishing
      # much by raising here (other than causing an unnecessary breakage).
      T::Configuration.log_info_handler(
        "chalk-odm: missing required property in serialize",
        prop: prop, class: self.class.name, id: self.class.decorator.get_id(self)
      )
    else
      raise TypeError.new("#{self.class.name}.#{prop} not set for non-optional prop")
    end
  end

  # Marks this property as missing during deserialize
  private def required_prop_missing_from_deserialize(prop)
    @_required_props_missing_from_deserialize ||= Set[]
    @_required_props_missing_from_deserialize << prop
    nil
  end

  private def raise_deserialization_error(prop_name, value, orig_error)
    T::Configuration.soft_assert_handler(
      'Deserialization error (probably unexpected stored type)',
      storytime: {
        klass: self.class,
        prop: prop_name,
        value: value,
        error: orig_error.message,
        notify: 'djudd'
      }
    )
  end
end

##############################################

# NB: This must stay in the same file where T::Props::Serializable is defined due to
# T::Props::Decorator#apply_plugin; see https://git.corp.stripe.com/stripe-internal/pay-server/blob/fc7f15593b49875f2d0499ffecfd19798bac05b3/chalk/odm/lib/chalk-odm/document_decorator.rb#L716-L717
module T::Props::Serializable::DecoratorMethods
  include T::Props::HasLazilySpecializedMethods::DecoratorMethods

  # Heads up!
  #
  # There are already too many ad-hoc options on the prop DSL.
  #
  # We have already done a lot of work to remove unnecessary and confusing
  # options. If you're considering adding a new rule key, please come chat with
  # the Sorbet team first, as we'd really like to learn more about how to best
  # solve the problem you're encountering.
  VALID_RULE_KEYS = {dont_store: true, name: true, raise_on_nil_write: true}.freeze
  private_constant :VALID_RULE_KEYS

  def valid_rule_key?(key)
    super || VALID_RULE_KEYS[key]
  end

  def required_props
    @class.props.select { |_, v| T::Props::Utils.required_prop?(v) }.keys
  end

  def prop_dont_store?(prop)
    prop_rules(prop)[:dont_store]
  end
  def prop_by_serialized_forms
    @class.prop_by_serialized_forms
  end

  def from_hash(hash, strict=false)
    raise ArgumentError.new("#{hash.inspect} provided to from_hash") if !(hash && hash.is_a?(Hash))

    i = @class.allocate
    i.deserialize(hash, strict)

    i
  end

  def prop_serialized_form(prop)
    prop_rules(prop)[:serialized_form]
  end

  def serialized_form_prop(serialized_form)
    prop_by_serialized_forms[serialized_form.to_s] || raise("No such serialized form: #{serialized_form.inspect}")
  end

  def add_prop_definition(prop, rules)
    serialized_form = rules.fetch(:name, prop.to_s)
    rules[:serialized_form] = serialized_form
    res = super
    prop_by_serialized_forms[serialized_form] = prop
    if T::Configuration.use_vm_prop_serde?
      enqueue_lazy_vm_method_definition!(:__t_props_generated_serialize) { generate_serialize2 }
      enqueue_lazy_vm_method_definition!(:__t_props_generated_deserialize) { generate_deserialize2 }
    else
      enqueue_lazy_method_definition!(:__t_props_generated_serialize) { generate_serialize_source }
      enqueue_lazy_method_definition!(:__t_props_generated_deserialize) { generate_deserialize_source }
    end
    res
  end

  private def generate_serialize_source
    T::Props::Private::SerializerGenerator.generate(props)
  end

  private def generate_deserialize_source
    T::Props::Private::DeserializerGenerator.generate(
      props,
      props_with_defaults || {},
    )
  end

  private def generate_serialize2
    T::Props::Private::SerializerGenerator.generate2(decorated_class, props)
  end

  private def generate_deserialize2
    T::Props::Private::DeserializerGenerator.generate2(
      decorated_class,
      props,
      props_with_defaults || {},
    )
  end

  def message_with_generated_source_context(error, generated_method, generate_source_method)
    generated_method = generated_method.to_s
    if error.backtrace_locations
      line_loc = error.backtrace_locations.find { |l| l.base_label == generated_method }
      return unless line_loc

      line_num = line_loc.lineno
    else
      label = if RUBY_VERSION >= "3.4"
        # in 'ClassName#__t_props_generated_serialize'"
        "##{generated_method}'"
      else
        # in `__t_props_generated_serialize'"
        "in `#{generated_method}'"
      end
      line_label = error.backtrace.find { |l| l.end_with?(label) }
      return unless line_label

      line_num = if line_label.start_with?("(eval)")
        # (eval):13:in ...
        line_label.split(':')[1]&.to_i
      else
        # (eval at /Users/jez/stripe/sorbet/gems/sorbet-runtime/lib/types/props/has_lazily_specialized_methods.rb:65):13:in ...
        line_label.split(':')[2]&.to_i
      end
    end
    return unless line_num

    source_lines = self.send(generate_source_method).split("\n")
    previous_blank = source_lines[0...line_num].rindex(&:empty?) || 0
    next_blank = line_num + (source_lines[line_num..-1]&.find_index(&:empty?) || 0)
    context = "  #{source_lines[(previous_blank + 1)...next_blank].join("\n  ")}"
    <<~MSG
      Error in #{decorated_class.name}##{generated_method}: #{error.message}
      at line #{line_num - previous_blank - 1} in:
      #{context}
    MSG
  end

  def raise_nil_deserialize_error(hkey)
    msg = "Tried to deserialize a required prop from a nil value. It's "\
      "possible that a nil value exists in the database, so you should "\
      "provide a `default: or factory:` for this prop (see go/optional "\
      "for more details). If this is already the case, you probably "\
      "omitted a required prop from the `fields:` option when doing a "\
      "partial load."
    storytime = {prop: hkey, klass: decorated_class.name}

    # Notify the model owner if it exists, and always notify the API owner.
    begin
      if T::Configuration.class_owner_finder && (owner = T::Configuration.class_owner_finder.call(decorated_class))
        T::Configuration.hard_assert_handler(
          msg,
          storytime: storytime,
          project: owner
        )
      end
    ensure
      T::Configuration.hard_assert_handler(msg, storytime: storytime)
    end
  end

  def prop_validate_definition!(name, cls, rules, type)
    result = super

    if (rules_name = rules[:name])
      unless rules_name.is_a?(String)
        raise ArgumentError.new("Invalid name in prop #{@class.name}.#{name}: #{rules_name.inspect}")
      end

      validate_prop_name(rules_name)
    end

    if !rules[:raise_on_nil_write].nil? && rules[:raise_on_nil_write] != true
      raise ArgumentError.new("The value of `raise_on_nil_write` if specified must be `true` (given: #{rules[:raise_on_nil_write]}).")
    end

    result
  end

  def get_id(instance)
    prop = prop_by_serialized_forms['_id']
    if prop
      get(instance, prop)
    else
      nil
    end
  end

  EMPTY_EXTRA_PROPS = {}.freeze
  private_constant :EMPTY_EXTRA_PROPS

  def extra_props(instance)
    if instance.instance_variable_defined?(:@_extra_props)
      instance.instance_variable_get(:@_extra_props) || EMPTY_EXTRA_PROPS
    else
      EMPTY_EXTRA_PROPS
    end
  end

  # adds to the default result of T::Props::PrettyPrintable
  def pretty_print_extra(instance, pp)
    # This is to maintain backwards compatibility with Stripe's codebase, where only the single line (through `inspect`)
    # version is expected to add anything extra
    return if !pp.is_a?(PP::SingleLine)
    if (extra_props = extra_props(instance)) && !extra_props.empty?
      pp.breakable
      pp.text("@_extra_props=")
      pp.group(1, "<", ">") do
        extra_props.each_with_index do |(prop, value), i|
          pp.breakable unless i.zero?
          pp.text("#{prop}=")
          value.pretty_print(pp)
        end
      end
    end
  end
end

##############################################

# NB: This must stay in the same file where T::Props::Serializable is defined due to
# T::Props::Decorator#apply_plugin; see https://git.corp.stripe.com/stripe-internal/pay-server/blob/fc7f15593b49875f2d0499ffecfd19798bac05b3/chalk/odm/lib/chalk-odm/document_decorator.rb#L716-L717
module T::Props::Serializable::ClassMethods
  def prop_by_serialized_forms
    @prop_by_serialized_forms ||= {}
  end

  # Allocate a new instance and call {#deserialize} to load a new
  # object from a hash.
  # @return [Serializable]
  def from_hash(hash, strict=false)
    self.decorator.from_hash(hash, strict)
  end

  # Equivalent to {.from_hash} with `strict` set to true.
  # @return [Serializable]
  def from_hash!(hash)
    self.decorator.from_hash(hash, true)
  end
end
