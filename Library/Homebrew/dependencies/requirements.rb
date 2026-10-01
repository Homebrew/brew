# typed: strict
# frozen_string_literal: true

# A collection of requirements.
class Requirements < SimpleDelegator
  extend T::Generic

  Elem = type_member(:out) { { fixed: Requirement } }

  sig { params(args: Requirement).void }
  def initialize(*args)
    super(Set.new(args))
  end

  sig { params(other: Requirement).returns(Requirements) }
  def <<(other)
    if other.is_a?(Comparable)
      __getobj__.grep(other.class) do |req|
        return self if req > other

        __getobj__.delete(req)
      end
    end
    # see https://sorbet.org/docs/faq#how-can-i-fix-type-errors-that-arise-from-super
    T.bind(self, T.untyped)
    super
    self
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: {#{__getobj__.to_a.join(", ")}}>"
  end
end
