# frozen_string_literal: true
# typed: false

module T::Props::Constructor
  include T::Props::WeakConstructor
end

module T::Props::Constructor::DecoratorMethods
  extend T::Sig

  # Set values for all props that have no defaults. Override what `WeakConstructor`
  # does in order to raise errors on nils instead of ignoring them.
  #
  # @return [Integer] A count of props that we successfully initialized (which
  # we'll use to check for any unrecognized input.)
  #
  # checked(:never) - O(runtime object construction)
  sig { params(instance: T::Props::Constructor, hash: T::Hash[Symbol, T.untyped]).returns(Integer).checked(:never) }
  def construct_props_without_defaults(instance, hash)
    # Use `each_pair` rather than `count` because, as of Ruby 2.6, the latter delegates to Enumerator
    # and therefore allocates for each entry.
    result = 0
    props_without_defaults&.each_pair do |p, setter_proc|
      begin
        val = hash[p]
        instance.instance_exec(val, &setter_proc)
        if val || hash.key?(p)
          result += 1
        end
      rescue TypeError, T::Props::InvalidValueError
        if !hash.key?(p)
          raise ArgumentError.new("Missing required prop `#{p}` for class `#{instance.class.name}`")
        else
          raise
        end
      end
    end
    result
  end
end
