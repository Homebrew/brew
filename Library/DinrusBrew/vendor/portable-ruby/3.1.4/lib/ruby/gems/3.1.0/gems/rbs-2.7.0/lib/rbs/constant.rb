# frozen_string_literal: true

module RBS
  class Constant
    attr_reader :name
    attr_reader :type
    attr_reader :entry

    def initialize(name:, type:, entry:)
      @name = name
      @type = type
      @entry = entry
    end

    def ==(other)
      other.is_a?(Constant) &&
        other.name == name &&
        other.type == type &&
        other.entry == entry
    end

    alias eql? ==

    def hash
      self.class.hash ^ name.hash ^ type.hash ^ entry.hash
    end
  end
end
