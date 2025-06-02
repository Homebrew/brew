# typed: strong
# frozen_string_literal: true

require "time"

class Time
  # Backwards compatibility for formulae that used this ActiveSupport extension
  alias rfc3339 xmlschema
end
