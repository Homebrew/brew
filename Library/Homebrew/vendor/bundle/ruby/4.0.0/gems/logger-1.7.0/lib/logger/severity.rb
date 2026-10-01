# frozen_string_literal: true

class Logger
  # Logging severity.
  module Severity
    # Low-level information, mostly for developers.
    DEBUG = 0
    # Generic (useful) information about system operation.
    INFO = 1
    # A warning.
    WARN = 2
    # A handleable error condition.
    ERROR = 3
    # An unhandleable error that results in a program crash.
    FATAL = 4
    # An unknown message that should always be logged.
    UNKNOWN = 5

    LEVELS = {
      "debug" => DEBUG,
      "info" => INFO,
      "warn" => WARN,
      "error" => ERROR,
      "fatal" => FATAL,
      "unknown" => UNKNOWN,
    }
    private_constant :LEVELS

    def self.coerce(severity)
      if severity.is_a?(Integer)
        severity
      else
        key = severity.to_s.downcase
        LEVELS[key] || raise(ArgumentError, "invalid log level: #{severity}")
      end
    end
  end
end
