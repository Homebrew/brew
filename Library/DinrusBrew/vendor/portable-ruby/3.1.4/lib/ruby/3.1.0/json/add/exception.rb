#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Exception

  # Deserializes JSON string by constructing new Exception object with message
  # <tt>m</tt> and backtrace <tt>b</tt> serialized with <tt>to_json</tt>
  def self.json_create(object)
    result = new(object['m'])
    result.set_backtrace object['b']
    result
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'm'            => message,
      'b'            => backtrace,
    }
  end

  # Stores class name (Exception) with message <tt>m</tt> and backtrace array
  # <tt>b</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end
