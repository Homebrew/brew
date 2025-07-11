# frozen_string_literal: true
# typed: true
require 'pp'

module T::Props::PrettyPrintable
  include T::Props::Plugin

  # Override the PP gem with something that's similar, but gives us a hook to do redaction and customization
  def pretty_print(pp)
    klass = T.unsafe(T.cast(self, Object).class).decorator
    multiline = pp.is_a?(PP)
    pp.group(1, "<#{klass.inspect_class_with_decoration(self)}", ">") do
      klass.all_props.sort.each do |prop|
        pp.breakable
        val = klass.get(self, prop)
        rules = klass.prop_rules(prop)
        pp.text("#{prop}=")
        if (custom_inspect = rules[:inspect])
          inspected = if T::Utils.arity(custom_inspect) == 1
            custom_inspect.call(val)
          else
            custom_inspect.call(val, {multiline: multiline})
          end
          pp.text(inspected.nil? ? "nil" : inspected)
        elsif rules[:sensitivity] && !rules[:sensitivity].empty? && !val.nil?
          pp.text("<REDACTED #{rules[:sensitivity].join(', ')}>")
        else
          val.pretty_print(pp)
        end
      end
      klass.pretty_print_extra(self, pp)
    end
  end

  # Return a string representation of this object and all of its props in a single line
  def inspect
    string = +""
    PP.singleline_pp(self, string)
    string
  end

  # Return a pretty string representation of this object and all of its props
  def pretty_inspect
    string = +""
    PP.pp(self, string)
    string
  end

  module DecoratorMethods
    extend T::Sig

    sig { params(key: Symbol).returns(T::Boolean).checked(:never) }
    def valid_rule_key?(key)
      super || key == :inspect
    end

    # Overridable method to specify how the first part of a `pretty_print`d object's class should look like
    # NOTE: This is just to support Stripe's `PrettyPrintableModel` case, and not recommended to be overridden
    sig { params(instance: T::Props::PrettyPrintable).returns(String) }
    def inspect_class_with_decoration(instance)
      T.unsafe(instance).class.to_s
    end

    # Overridable method to add anything that is not a prop
    # NOTE: This is to support cases like Serializable's `@_extra_props`, and Stripe's `PrettyPrintableModel#@_deleted`
    sig { params(instance: T::Props::PrettyPrintable, pp: T.any(PrettyPrint, PP::SingleLine)).void }
    def pretty_print_extra(instance, pp); end
  end
end
