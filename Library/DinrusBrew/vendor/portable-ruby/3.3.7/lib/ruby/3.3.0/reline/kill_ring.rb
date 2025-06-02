class Reline::KillRing
  include Enumerable

  module State
    FRESH = :fresh
    CONTINUED = :continued
    PROCESSED = :processed
    YANK = :yank
  end

  RingPoint = Struct.new(:backward, :forward, :str) do
    def initialize(str)
      super(nil, nil, str)
    end

    def ==(other)
      equal?(other)
    end
  end

  class RingBuffer
    attr_reader :size
    attr_reader :head

    def initialize(max = 1024)
      @max = max
      @size = 0
      @head = nil # reading head of ring-shaped tape
    end

    def <<(point)
      if @size.zero?
        @head = point
        @head.backward = @head
        @head.forward = @head
        @size = 1
      elsif @size >= @max
        tail = @head.forward
        new_tail = tail.forward
        @head.forward = point
        point.backward = @head
        new_tail.backward = point
        point.forward = new_tail
        @head = point
      else
        tail = @head.forward
        @head.forward = point
        point.backward = @head
        tail.backward = point
        point.forward = tail
        @head = point
        @size += 1
      end
    end

    def empty?
      @size.zero?
    end
  end

  def initialize(max = 1024)
    @ring = RingBuffer.new(max)
    @ring_pointer = nil
    @buffer = nil
    @state = State::FRESH
  end

  def append(string, before_p = false)
    case @state
    when State::FRESH, State::YANK
      @ring << RingPoint.new(+string)
      @state = State::CONTINUED
    when State::CONTINUED, State::PROCESSED
      if before_p
        @ring.head.str.prepend(string)
      else
        @ring.head.str.concat(string)
      end
      @state = State::CONTINUED
    end
  end

  def process
    case @state
    when State::FRESH
      # nothing to do
    when State::CONTINUED
      @state = State::PROCESSED
    when State::PROCESSED
      @state = State::FRESH
    when State::YANK
      # nothing to do
    end
  end

  def yank
    unless @ring.empty?
      @state = State::YANK
      @ring_pointer = @ring.head
      @ring_pointer.str
    else
      nil
    end
  end

  def yank_pop
    if @state == State::YANK
      prev_yank = @ring_pointer.str
      @ring_pointer = @ring_pointer.backward
      [@ring_pointer.str, prev_yank]
    else
      nil
    end
  end

  def each
    start = head = @ring.head
    loop do
      break if head.nil?
      yield head.str
      head = head.backward
      break if head == start
    end
  end
end
