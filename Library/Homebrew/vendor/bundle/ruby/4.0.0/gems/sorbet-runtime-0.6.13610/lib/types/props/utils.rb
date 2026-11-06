# frozen_string_literal: true
# typed: true

module T::Props::Utils
  # Deep copy an object. The object must consist of Ruby primitive
  # types and Hashes and Arrays.
  def self.deep_clone_object(what, freeze: false)
    freeze ? deep_clone_freeze(what) : deep_clone(what)
  end

  # deep_clone_object with freeze: false. Kept kwarg-free, with String (the
  # most common serialized scalar) tested first: this is what generated
  # serializers/deserializers emit for dynamic fallbacks, so it runs per
  # element of every untyped container prop.
  def self.deep_clone(what)
    case what
    when String
      what.clone
    when true, false, Symbol, NilClass, Numeric
      what
    when Array
      what.map { |v| deep_clone(v) }
    when Hash
      h = what.class.new
      what.each_pair do |k, v|
        h[k] = deep_clone(v)
      end
      h
    when Regexp
      what.dup
    when T::Enum
      what
    else
      what.clone
    end
  end

  # deep_clone_object with freeze: true.
  def self.deep_clone_freeze(what)
    result = case what
    when true, false, Symbol, NilClass, Numeric
      what
    when Array
      what.map { |v| deep_clone_freeze(v) }
    when Hash
      h = what.class.new
      what.each_pair do |k, v|
        k.freeze
        h[k] = deep_clone_freeze(v)
      end
      h
    when Regexp
      what.dup
    when T::Enum
      what
    else
      what.clone
    end
    result.freeze
  end

  # The prop_rules indicate whether we should check for reading a nil value for the prop/field.
  # This is mostly for the compatibility check that we allow existing documents carry some nil prop/field.
  def self.need_nil_read_check?(prop_rules)
    # . :on_load allows nil read, but we need to check for the read for future writes
    prop_rules[:optional] == :on_load || prop_rules[:raise_on_nil_write]
  end

  # The prop_rules indicate whether we should check for writing a nil value for the prop/field.
  def self.need_nil_write_check?(prop_rules)
    need_nil_read_check?(prop_rules) || T::Props::Utils.required_prop?(prop_rules)
  end

  def self.required_prop?(prop_rules)
    # Clients should never reference :_tnilable as the implementation can change.
    !prop_rules[:_tnilable]
  end

  def self.optional_prop?(prop_rules)
    # Clients should never reference :_tnilable as the implementation can change.
    !!prop_rules[:_tnilable]
  end

  def self.merge_serialized_optional_rule(prop_rules)
    {'_tnilable' => true}.merge(prop_rules.merge('_tnilable' => true))
  end
end
