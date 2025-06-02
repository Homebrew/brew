class Reline::History < Array
  def initialize(config)
    @config = config
  end

  def to_s
    'HISTORY'
  end

  def delete_at(index)
    index = check_index(index)
    super(index)
  end

  def [](index)
    index = check_index(index) unless index.is_a?(Range)
    super(index)
  end

  def []=(index, val)
    index = check_index(index)
    super(index, String.new(val, encoding: Reline.encoding_system_needs))
  end

  def concat(*val)
    val.each do |v|
      push(*v)
    end
  end

  def push(*val)
    # If history_size is zero, all histories are dropped.
    return self if @config.history_size.zero?
    # If history_size is negative, history size is unlimited.
    if @config.history_size.positive?
      diff = size + val.size - @config.history_size
      if diff > 0
        if diff <= size
          shift(diff)
        else
          diff -= size
          clear
          val.shift(diff)
        end
      end
    end
    super(*(val.map{ |v|
      String.new(v, encoding: Reline.encoding_system_needs)
    }))
  end

  def <<(val)
    # If history_size is zero, all histories are dropped.
    return self if @config.history_size.zero?
    # If history_size is negative, history size is unlimited.
    if @config.history_size.positive?
      shift if size + 1 > @config.history_size
    end
    super(String.new(val, encoding: Reline.encoding_system_needs))
  end

  private def check_index(index)
    index += size if index < 0
    if index < -2147483648 or 2147483647 < index
      raise RangeError.new("integer #{index} too big to convert to `int'")
    end
    # If history_size is negative, history size is unlimited.
    if @config.history_size.positive?
      if index < -@config.history_size or @config.history_size < index
        raise RangeError.new("index=<#{index}>")
      end
    end
    raise IndexError.new("index=<#{index}>") if index < 0 or size <= index
    index
  end
end
