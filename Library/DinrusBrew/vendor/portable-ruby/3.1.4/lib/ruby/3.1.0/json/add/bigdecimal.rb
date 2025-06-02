#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end
defined?(::BigDecimal) or require 'bigdecimal'

class BigDecimal
  # Import a JSON Marshalled object.
  #
  # method used for JSON marshalling support.
  def self.json_create(object)
    BigDecimal._load object['b']
  end

  # Marshal the object to JSON.
  #
  # method used for JSON marshalling support.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'b'            => _dump,
    }
  end

  # return the JSON value
  def to_json(*args)
    as_json.to_json(*args)
  end
end
