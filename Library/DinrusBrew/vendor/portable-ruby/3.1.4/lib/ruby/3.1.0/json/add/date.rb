#frozen_string_literal: false
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end
require 'date'

class Date

  # Deserializes JSON string by converting Julian year <tt>y</tt>, month
  # <tt>m</tt>, day <tt>d</tt> and Day of Calendar Reform <tt>sg</tt> to Date.
  def self.json_create(object)
    civil(*object.values_at('y', 'm', 'd', 'sg'))
  end

  alias start sg unless method_defined?(:start)

  # Returns a hash, that will be turned into a JSON object and represent this
  # object.
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      'y' => year,
      'm' => month,
      'd' => day,
      'sg' => start,
    }
  end

  # Stores class name (Date) with Julian year <tt>y</tt>, month <tt>m</tt>, day
  # <tt>d</tt> and Day of Calendar Reform <tt>sg</tt> as JSON string
  def to_json(*args)
    as_json.to_json(*args)
  end
end
