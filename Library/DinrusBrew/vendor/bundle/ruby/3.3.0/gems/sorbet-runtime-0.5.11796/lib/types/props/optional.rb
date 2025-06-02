# frozen_string_literal: true
# typed: false

module T::Props::Optional
  include T::Props::Plugin
end

##############################################

# NB: This must stay in the same file where T::Props::Optional is defined due to
# T::Props::Decorator#apply_plugin; see https://git.corp.stripe.com/stripe-internal/pay-server/blob/fc7f15593b49875f2d0499ffecfd19798bac05b3/chalk/odm/lib/chalk-odm/document_decorator.rb#L716-L717
module T::Props::Optional::DecoratorMethods
  extend T::Sig

  # Heads up!
  #
  # There are already too many ad-hoc options on the prop DSL.
  #
  # We have already done a lot of work to remove unnecessary and confusing
  # options. If you're considering adding a new rule key, please come chat with
  # the Sorbet team first, as we'd really like to learn more about how to best
  # solve the problem you're encountering.
  VALID_RULE_KEYS = {
    default: true,
    factory: true,
  }.freeze
  private_constant :VALID_RULE_KEYS

  DEFAULT_SETTER_RULE_KEY = :_t_props_private_apply_default
  private_constant :DEFAULT_SETTER_RULE_KEY

  def valid_rule_key?(key)
    super || VALID_RULE_KEYS[key]
  end

  def prop_optional?(prop)
    prop_rules(prop)[:fully_optional]
  end

  def compute_derived_rules(rules)
    rules[:fully_optional] = !T::Props::Utils.need_nil_write_check?(rules)
    rules[:need_nil_read_check] = T::Props::Utils.need_nil_read_check?(rules)
  end

  # checked(:never) - O(runtime object construction)
  sig {returns(T::Hash[Symbol, T::Props::Private::ApplyDefault]).checked(:never)}
  attr_reader :props_with_defaults

  # checked(:never) - O(runtime object construction)
  sig {returns(T::Hash[Symbol, T::Props::Private::SetterFactory::SetterProc]).checked(:never)}
  attr_reader :props_without_defaults

  def add_prop_definition(prop, rules)
    compute_derived_rules(rules)

    default_setter = T::Props::Private::ApplyDefault.for(decorated_class, rules)
    if default_setter
      @props_with_defaults ||= {}
      @props_with_defaults[prop] = default_setter
      props_without_defaults&.delete(prop) # Handle potential override

      rules[DEFAULT_SETTER_RULE_KEY] = default_setter
    else
      @props_without_defaults ||= {}
      @props_without_defaults[prop] = rules.fetch(:setter_proc)
      props_with_defaults&.delete(prop) # Handle potential override
    end

    super
  end

  def prop_validate_definition!(name, cls, rules, type)
    result = super

    if rules.key?(:default) && rules.key?(:factory)
      raise ArgumentError.new("Setting both :default and :factory is invalid. See: go/chalk-docs")
    end

    result
  end

  def has_default?(rules)
    rules.include?(DEFAULT_SETTER_RULE_KEY)
  end

  def get_default(rules, instance_class)
    rules[DEFAULT_SETTER_RULE_KEY]&.default
  end
end
