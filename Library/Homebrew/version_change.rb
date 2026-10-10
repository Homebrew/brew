# typed: strict
# frozen_string_literal: true

# A package version change as listed in install and upgrade summaries.
class VersionChange < T::Struct
  const :name, String
  const :old_version, T.nilable(String), default: nil
  const :new_version, String
  # The download size, e.g. `2.4MB`.
  const :size, T.nilable(String), default: nil

  sig { params(other: BasicObject).returns(T::Boolean) }
  def ==(other)
    case other
    when VersionChange then values == other.values
    else false
    end
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash = values.hash

  protected

  sig { returns(T::Array[T.nilable(String)]) }
  def values = [name, old_version, new_version, size]
end
