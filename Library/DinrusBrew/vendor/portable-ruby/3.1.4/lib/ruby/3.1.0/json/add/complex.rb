#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Complex

  # Deserializes JSON string by converting Real value <tt>r</tt>, imaginary
  # value <tt>i</tt>, to a Complex object.
  def self.json_create(object)
    Complex(object['r'], object['i'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'r'            => real,
      'i'            => imag,
    }
  end

  # Stores class name (Complex) along with real value <tt>r</tt> and imaginary value <tt>i</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end
