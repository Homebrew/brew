unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end
defined?(::Set) or require 'set'

class Set
  # Import a JSON Marshalled object.
  #
  # method used for JSON marshalling support.
  def self.json_create(object)
    new object['a']
  end

  # Marshal the object to JSON.
  #
  # method used for JSON marshalling support.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'a'            => to_a,
    }
  end

  # return the JSON value
  def to_json(*args)
    as_json.to_json(*args)
  end
end

