# frozen_string_literal: true

module Protobug
  class Registry
    def initialize(&blk)
      @registry = {}
      return unless blk

      yield self
      freeze
    end

    def freeze
      @registry.freeze
      super
    end

    def register(klass)
      unless klass.is_a? Protobug::BaseDescriptor
        raise ArgumentError,
              "expected Protobug::BaseDescriptor, got #{klass.inspect}"
      end

      full_name = klass.full_name
      existing = @registry[full_name]
      raise ArgumentError, "duplicate class #{full_name}" if existing && existing != klass

      @registry[full_name] = klass
      klass.freeze
    end

    def fetch(...)
      @registry.fetch(...)
    end
  end
end
