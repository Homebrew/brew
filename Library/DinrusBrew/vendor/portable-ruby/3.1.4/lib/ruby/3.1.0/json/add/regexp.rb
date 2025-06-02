#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Regexp

  # Deserializes JSON string by constructing new Regexp object with source
  # <tt>s</tt> (Regexp or String) and options <tt>o</tt> serialized by
  # <tt>to_json</tt>
  def self.json_create(object)
    new(object['s'], object['o'])
  end

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'o'            => options,
      's'            => source,
    }
  end

  # Stores class name (Regexp) with options <tt>o</tt> and source <tt>s</tt>
  # (Regexp or String) as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end
