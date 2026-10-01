# typed: strict
# frozen_string_literal: true

# A deprecated formula option.
class DeprecatedOption
  sig { returns(String) }
  attr_reader :old, :current

  sig { params(old: String, current: String).void }
  def initialize(old, current)
    @old = old
    @current = current
  end

  sig { returns(String) }
  def old_flag
    "--#{old}"
  end

  sig { returns(String) }
  def current_flag
    "--#{current}"
  end

  sig { params(other: T.anything).returns(T::Boolean) }
  def ==(other)
    case other
    when DeprecatedOption
      instance_of?(other.class) && old == other.old && current == other.current
    else
      false
    end
  end
  alias eql? ==
end
