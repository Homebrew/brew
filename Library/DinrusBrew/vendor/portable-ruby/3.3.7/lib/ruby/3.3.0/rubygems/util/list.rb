# frozen_string_literal: true

module Gem
  # The Gem::List class is currently unused and will be removed in the next major rubygems version
  class List # :nodoc:
    include Enumerable
    attr_accessor :value, :tail

    def initialize(value = nil, tail = nil)
      @value = value
      @tail = tail
    end

    def each
      n = self
      while n
        yield n.value
        n = n.tail
      end
    end

    def to_a
      super.reverse
    end

    def prepend(value)
      List.new value, self
    end

    def pretty_print(q) # :nodoc:
      q.pp to_a
    end

    def self.prepend(list, value)
      return List.new(value) unless list
      List.new value, list
    end
  end
  deprecate_constant :List
end
