# frozen_string_literal: true

require 'delegate'

module ELFTools
  # A helper class for {ELFTools} easy to implement
  # 'lazy loading' objects.
  # Mainly used when loading sections, segments, and
  # symbols.
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
      super(Array.new(size))
      @block = block
    end

    # To access elements like a normal array.
    #
    # Elements are lazy loaded at the first time
    # access it.
    # @return [Object]
    #   The element, returned type is the
    #   return type of block given in {#initialize}.
    def [](i)
      # XXX: support negative index?
      return nil unless i.between?(0, __getobj__.size - 1)

      __getobj__[i] ||= @block.call(i)
    end
  end
end
