class Reline::KeyStroke
  def initialize(config)
    @config = config
  end

  def compress_meta_key(ary)
    return ary unless @config.convert_meta
    ary.inject([]) { |result, key|
      if result.size > 0 and result.last == "\e".ord
        result[result.size - 1] = Reline::Key.new(key, key | 0b10000000, true)
      else
        result << key
      end
      result
    }
  end

  def start_with?(me, other)
    compressed_me = compress_meta_key(me)
    compressed_other = compress_meta_key(other)
    i = 0
    loop do
      my_c = compressed_me[i]
      other_c = compressed_other[i]
      other_is_last = (i + 1) == compressed_other.size
      me_is_last = (i + 1) == compressed_me.size
      if my_c != other_c
        if other_c == "\e".ord and other_is_last and my_c.is_a?(Reline::Key) and my_c.with_meta
          return true
        else
          return false
        end
      elsif other_is_last
        return true
      elsif me_is_last
        return false
      end
      i += 1
    end
  end

  def equal?(me, other)
    case me
    when Array
      compressed_me = compress_meta_key(me)
      compressed_other = compress_meta_key(other)
      compressed_me.size == compressed_other.size and [compressed_me, compressed_other].transpose.all?{ |i| equal?(i[0], i[1]) }
    when Integer
      if other.is_a?(Reline::Key)
        if other.combined_char == "\e".ord
          false
        else
          other.combined_char == me
        end
      else
        me == other
      end
    when Reline::Key
      if other.is_a?(Integer)
        me.combined_char == other
      else
        me == other
      end
    end
  end

  def match_status(input)
    key_mapping.keys.select { |lhs|
      start_with?(lhs, input)
    }.tap { |it|
      return :matched  if it.size == 1 && equal?(it[0], input)
      return :matching if it.size == 1 && !equal?(it[0], input)
      return :matched  if it.max_by(&:size)&.size&.< input.size
      return :matching if it.size > 1
    }
    key_mapping.keys.select { |lhs|
      start_with?(input, lhs)
    }.tap { |it|
      return it.size > 0 ? :matched : :unmatched
    }
  end

  def expand(input)
    input = compress_meta_key(input)
    lhs = key_mapping.keys.select { |item| start_with?(input, item) }.sort_by(&:size).last
    return input unless lhs
    rhs = key_mapping[lhs]

    case rhs
    when String
      rhs_bytes = rhs.bytes
      expand(expand(rhs_bytes) + expand(input.drop(lhs.size)))
    when Symbol
      [rhs] + expand(input.drop(lhs.size))
    when Array
      rhs
    end
  end

  private

  def key_mapping
    @config.key_bindings
  end
end
