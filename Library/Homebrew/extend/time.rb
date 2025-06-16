# typed: strong
# frozen_string_literal: true

require "time"

class Time
  # Backwards compatibility for formulae that used this ActiveSupport extension
  sig { returns(String) }
  def rfc3339
    odeprecated "Time#rfc3339", "Time#xmlschema"
    xmlschema
  end
end
