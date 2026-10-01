# frozen_string_literal: true
# typed: true

module T::Types
  # validates that the provided value is within a given set/enum
  class Enum < Base
    extend T::Sig

    attr_reader :values

    def initialize(values)
      case values
      when Hash
        @values = values
      else
        require "set" unless defined?(Set)
        @values = values.to_set
      end
    end

    def build_type
      nil
    end

    # overrides Base
    def valid?(obj)
      @values.member?(obj)
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when Enum
        (@values - other.values).empty?
      else
        false
      end
    end

    # overrides Base
    def name
      @name ||= "T.deprecated_enum([#{@values.map(&:inspect).sort.join(', ')}])"
    end

    # overrides Base
    def describe_obj(obj)
      obj.inspect
    end
  end
end
