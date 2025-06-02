#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end
require 'ostruct'

class OpenStruct

  # Deserializes JSON string by constructing new Struct object with values
  # <tt>t</tt> serialized by <tt>to_json</tt>.
  def self.json_create(object)
    new(object['t'] || object[:t])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    klass = self.class.name
    klass.to_s.empty? and raise JSON::JSONError, "Only named structs are supported!"
    {
      JSON.create_id => klass,
      't'            => table,
    }
  end

  # Stores class name (OpenStruct) with this struct's values <tt>t</tt> as a
  # JSON string.
  def to_json(*args)
    as_json.to_json(*args)
  end
end
