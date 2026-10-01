# typed: strict
# frozen_string_literal: true

class Hash
  # Returns a deep copy of hash.
  #
  #   hash = { a: { b: 'b' } }
  #   dup  = hash.deep_dup
  #   dup[:a][:c] = 'c'
  #
  #   hash[:a][:c] # => nil
  #   dup[:a][:c]  # => "c"
  sig { returns(T.self_type) }
  def deep_dup
    hash = dup
    each_pair do |key, value|
      duplicated_value = case value
      when ::Object then value.deep_dup
      else value
      end

      case key
      when ::String, ::Symbol
        hash[key] = duplicated_value
      when ::Object
        hash.delete(key)
        hash[key.deep_dup] = duplicated_value
      end
    end
    hash
  end
end
