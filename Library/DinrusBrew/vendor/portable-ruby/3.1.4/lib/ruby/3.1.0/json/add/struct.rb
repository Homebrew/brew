#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Struct

  # Deserializes JSON string by constructing new Struct object with values
  # <tt>v</tt> serialized by <tt>to_json</tt>.
  def self.json_create(object)
    new(*object['v'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    klass = self.class.name
    klass.to_s.empty? and raise JSON::JSONError, "Only named structs are supported!"
    {
      JSON.create_id => klass,
      'v'            => values,
    }
  end

  # Stores class name (Struct) with Struct values <tt>v</tt> as a JSON string.
  # Only named structs are supported.
  def to_json(*args)
    as_json.to_json(*args)
  end
end
