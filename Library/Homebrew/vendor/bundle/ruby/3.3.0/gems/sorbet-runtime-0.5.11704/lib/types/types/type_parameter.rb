# frozen_string_literal: true
# typed: true

module T::Types
  class TypeParameter < Base
    module Private
      @pool = {}

      def self.cached_entry(name)
        @pool[name]
      end

      def self.set_entry_for(name, type)
        @pool[name] = type
      end
    end

    def initialize(name)
      raise ArgumentError.new("not a symbol: #{name}") unless name.is_a?(Symbol)
      @name = name
    end

    def build_type
      nil
    end

    def self.make(name)
      cached = Private.cached_entry(name)
      return cached if cached

      Private.set_entry_for(name, new(name))
    end

    def valid?(obj)
      true
    end

    def subtype_of_single?(type)
      true
    end

    def name
      "T.type_parameter(:#{@name})"
    end
  end
end
