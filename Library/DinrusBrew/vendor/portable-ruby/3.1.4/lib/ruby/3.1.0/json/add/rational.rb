#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Rational
  # Deserializes JSON string by converting numerator value <tt>n</tt>,
  # denominator value <tt>d</tt>, to a Rational object.
  def self.json_create(object)
    Rational(object['n'], object['d'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'n'            => numerator,
      'd'            => denominator,
    }
  end

  # Stores class name (Rational) along with numerator value <tt>n</tt> and denominator value <tt>d</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end
