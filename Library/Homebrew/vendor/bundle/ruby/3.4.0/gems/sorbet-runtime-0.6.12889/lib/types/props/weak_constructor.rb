# frozen_string_literal: true
# typed: false

module T::Props::WeakConstructor
  include T::Props::Optional
  extend T::Sig

  # checked(:never) - O(runtime object construction)
  sig { params(hash: T::Hash[Symbol, T.untyped]).void.checked(:never) }
  def initialize(hash={})
    decorator = self.class.decorator

    hash_keys_matching_props = decorator.construct_props_with_defaults(self, hash) +
      decorator.construct_props_without_defaults(self, hash)

    if hash_keys_matching_props < hash.size
      raise ArgumentError.new("#{self.class}: Unrecognized properties: #{(hash.keys - decorator.props.keys).join(', ')}")
    end
  end
end

module T::Props::WeakConstructor::DecoratorMethods
  extend T::Sig

  # Set values for all props that have no defaults. Ignore any not present.
  #
  # @return [Integer] A count of props that we successfully initialized (which
  # we'll use to check for any unrecognized input.)
  #
  # checked(:never) - O(runtime object construction)
  sig { params(instance: T::Props::WeakConstructor, hash: T::Hash[Symbol, T.untyped]).returns(Integer).checked(:never) }
  def construct_props_without_defaults(instance, hash)
    # Use `each_pair` rather than `count` because, as of Ruby 2.6, the latter delegates to Enumerator
    # and therefore allocates for each entry.
    result = 0
    props_without_defaults&.each_pair do |p, setter_proc|
      if hash.key?(p)
        instance.instance_exec(hash[p], &setter_proc)
        result += 1
      end
    end
    result
  end

  # Set values for all props that have defaults. Use the default if and only if
  # the prop key isn't in the input.
  #
  # @return [Integer] A count of props that we successfully initialized (which
  # we'll use to check for any unrecognized input.)
  #
  # checked(:never) - O(runtime object construction)
  sig { params(instance: T::Props::WeakConstructor, hash: T::Hash[Symbol, T.untyped]).returns(Integer).checked(:never) }
  def construct_props_with_defaults(instance, hash)
    # Use `each_pair` rather than `count` because, as of Ruby 2.6, the latter delegates to Enumerator
    # and therefore allocates for each entry.
    result = 0
    props_with_defaults&.each_pair do |p, default_struct|
      if hash.key?(p)
        instance.instance_exec(hash[p], &default_struct.setter_proc)
        result += 1
      else
        default_struct.set_default(instance)
      end
    end
    result
  end
end
