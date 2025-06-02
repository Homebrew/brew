# frozen_string_literal: true

module SyntaxSuggest
  # Keeps track of what elements are in the queue in
  # priority and also ensures that when one element
  # engulfs/covers/eats another that the larger element
  # evicts the smaller element
  class PriorityEngulfQueue
    def initialize
      @queue = PriorityQueue.new
    end

    def to_a
      @queue.to_a
    end

    def empty?
      @queue.empty?
    end

    def length
      @queue.length
    end

    def peek
      @queue.peek
    end

    def pop
      @queue.pop
    end

    def push(block)
      prune_engulf(block)
      @queue << block
      flush_deleted

      self
    end

    private def flush_deleted
      while @queue&.peek&.deleted?
        @queue.pop
      end
    end

    private def prune_engulf(block)
      # If we're about to pop off the same block, we can skip deleting
      # things from the frontier this iteration since we'll get it
      # on the next iteration
      return if @queue.peek && (block <=> @queue.peek) == 1

      if block.starts_at != block.ends_at # A block of size 1 cannot engulf another
        @queue.to_a.each { |b|
          if b.starts_at >= block.starts_at && b.ends_at <= block.ends_at
            b.delete
            true
          end
        }
      end
    end
  end
end
