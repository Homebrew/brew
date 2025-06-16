# typed: strict
# frozen_string_literal: true

# A formula's checksum.
class Checksum
  extend Forwardable

  sig { returns(String) }
  attr_reader :hexdigest

  sig { params(hexdigest: String).void }
  def initialize(hexdigest)
    @hexdigest = T.let(hexdigest.downcase, String)
  end

  delegate [:empty?, :to_s, :length, :[]] => :@hexdigest

  sig { params(other: T.any(String, Checksum, Symbol)).returns(T::Boolean) }
  def ==(other)
    case other
    when String
      to_s == other.downcase
    when Checksum
      hexdigest == other.hexdigest
    else
      false
    end
  end
end
