# frozen_string_literal: true

module Bundler
  module SafeMarshal
    ALLOWED_CLASSES = [
      Array,
      FalseClass,
      Gem::Specification,
      Gem::Version,
      Hash,
      String,
      Symbol,
      Time,
      TrueClass,
    ].freeze

    ERROR = "Unexpected class %s present in marshaled data. Only %s are allowed."

    PROC = proc do |object|
      object.tap do
        unless ALLOWED_CLASSES.include?(object.class)
          raise TypeError, format(ERROR, object.class, ALLOWED_CLASSES.join(", "))
        end
      end
    end

    def self.proc
      PROC
    end
  end
end
