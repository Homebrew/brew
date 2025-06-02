# typed: strict

class Hash
  sig { returns(T::Hash[Hash::K, Hash::V]) }
  def compact_blank; end
end
