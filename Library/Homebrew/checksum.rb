# typed: true
# frozen_string_literal: true

# A formula's checksum.
class Checksum
  extend Forwardable

  attr_reader :hexdigest

  def initialize(hexdigest)
    @hexdigest = hexdigest.downcase
  end

  delegate [:empty?, :to_s, :length, :[]] => :@hexdigest

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
