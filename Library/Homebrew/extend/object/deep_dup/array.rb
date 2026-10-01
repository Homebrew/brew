# typed: strict
# frozen_string_literal: true

class Array
  # Returns a deep copy of array.
  #
  #   array = [1, [2, 3]]
  #   dup   = array.deep_dup
  #   dup[1][2] = 4
  #
  #   array[1][2] # => nil
  #   dup[1][2]   # => 4
  sig { returns(T.self_type) }
  def deep_dup
    dup.map! do |element|
      case element
      when Object then element.deep_dup
      else element
      end
    end
  end
end
