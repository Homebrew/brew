# frozen_string_literal: true
# typed: true

# Holds a string. Useful for showing type aliases in error messages
class T::Private::Types::StringHolder < T::Types::Base
  attr_reader :string

  def initialize(string)
    @string = string
  end

  def build_type
    nil
  end

  # overrides Base
  def name
    string
  end

  # overrides Base
  def valid?(obj)
    false
  end

  # overrides Base
  private def subtype_of_single?(other)
    false
  end
end
