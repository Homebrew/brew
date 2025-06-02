# frozen_string_literal: true

module SyntaxSuggest
  # Holds elements in a priority heap on insert
  #
  # Instead of constantly calling `sort!`, put
  # the element where it belongs the first time
  # around
  #
  # Example:
  #
  #   queue = PriorityQueue.new
  #   queue << 33
  #   queue << 44
  #   queue << 1
  #
  #   puts queue.peek # => 44
  #
  class PriorityQueue
    attr_reader :elements

    def initialize
      @elements = []
    end

    def <<(element)
      @elements << element
      bubble_up(last_index, element)
    end

    def pop
      exchange(0, last_index)
      max = @elements.pop
      bubble_down(0)
      max
    end

    def length
      @elements.length
    end

    def empty?
      @elements.empty?
    end

    def peek
      @elements.first
    end

    def to_a
      @elements
    end

    # Used for testing, extremely not performant
    def sorted
      out = []
      elements = @elements.dup
      while (element = pop)
        out << element
      end
      @elements = elements
      out.reverse
    end

    private def last_index
      @elements.size - 1
    end

    private def bubble_up(index, element)
      return if index <= 0

      parent_index = (index - 1) / 2
      parent = @elements[parent_index]

      return if (parent <=> element) >= 0

      exchange(index, parent_index)
      bubble_up(parent_index, element)
    end

    private def bubble_down(index)
      child_index = (index * 2) + 1

      return if child_index > last_index

      not_the_last_element = child_index < last_index
      left_element = @elements[child_index]
      right_element = @elements[child_index + 1]

      child_index += 1 if not_the_last_element && (right_element <=> left_element) == 1

      return if (@elements[index] <=> @elements[child_index]) >= 0

      exchange(index, child_index)
      bubble_down(child_index)
    end

    def exchange(source, target)
      a = @elements[source]
      b = @elements[target]
      @elements[source] = b
      @elements[target] = a
    end
  end
end
