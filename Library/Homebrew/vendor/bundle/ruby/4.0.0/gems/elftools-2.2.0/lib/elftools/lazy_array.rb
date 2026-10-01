# frozen_string_literal: true

require 'delegate'

module ELFTools
  # A helper class for {ELFTools} easy to implement
  # 'lazy loading' objects.
  # Mainly used when loading sections, segments, and
  # symbols.
  #
  # Only {#[]} loads an element on demand, any other method
  # of +Array+ loads all elements before it operates.
  class LazyArray < SimpleDelegator
    # Instantiate a {LazyArray} object.
    # @param [Integer] size
    #   The size of array.
    # @yieldparam [Integer] i
    #   Needs the +i+-th element.
    # @yieldreturn [Object]
    #   Value of the +i+-th element.
    # @example
    #   arr = LazyArray.new(10) { |i| p "calc #{i}"; i * i }
    #   p arr[2]
    #   # "calc 2"
    #   # 4
    #
    #   p arr[3]
    #   # "calc 3"
    #   # 9
    #
    #   p arr[3]
    #   # 9
    def initialize(size, &block)
      @array = Array.new(size)
      super(@array)
      @block = block
    end

    # To access elements like a normal array.
    #
    # Elements are lazy loaded at the first time
    # access it.
    # @param [Integer] i
    #   The index, negative index is *not* supported.
    # @return [Object]
    #   The element, returned type is the
    #   return type of block given in {#initialize}.
    #   +nil+ if +i+ is out of bound.
    def [](i)
      return nil unless i.between?(0, size - 1)

      @array[i] ||= @block.call(i)
    end

    # The size of this array.
    #
    # This method never loads any element.
    # @return [Integer]
    #   The size given in {#initialize}.
    def size
      @array.size
    end
    alias length size

    # Loads all elements.
    #
    # Called whenever a method other than {#[]} and {#size} is invoked, so that
    # those methods operate on a fully loaded array.
    # @return [Array]
    #   The loaded array.
    # @example
    #   arr = LazyArray.new(3) { |i| i * i }
    #   p arr.map { |v| v + 1 }
    #   # [1, 2, 5]
    def __getobj__
      @array.each_index { |i| self[i] }
      @array
    end

    private

    # Queries the array without loading any element.
    def respond_to_missing?(name, include_private = false)
      @array.respond_to?(name, include_private)
    end
  end
end
