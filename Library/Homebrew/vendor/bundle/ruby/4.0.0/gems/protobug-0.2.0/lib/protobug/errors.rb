# frozen_string_literal: true

module Protobug
  class Error < StandardError
  end

  class UnsupportedFeatureError < Error
    def initialize(feature, msg)
      @feature = feature
      super("feature #{feature} is unsupported: #{msg}")
    end
  end

  class EncodeError < Error
  end

  class DecodeError < Error
  end

  class UnknownFieldError < DecodeError
  end

  class DefinitionError < Error
  end

  class InvalidValueError < Error
    def initialize(msg, field, value, message = "")
      super("invalid value for #{field.name} (#{field.number}, #{field.inspect}) of #{msg.class.full_name}: " \
            "#{value.inspect}#{" (#{message})" if message}")
    end
  end
end
