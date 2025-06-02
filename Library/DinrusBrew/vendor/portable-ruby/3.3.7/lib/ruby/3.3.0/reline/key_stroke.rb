class Reline::KeyStroke
  ESC_BYTE = 27
  CSI_PARAMETER_BYTES_RANGE = 0x30..0x3f
  CSI_INTERMEDIATE_BYTES_RANGE = (0x20..0x2f)

  def initialize(config)
    @config = config
  end

  # Input exactly matches to a key sequence
  MATCHING = :matching
  # Input partially matches to a key sequence
  MATCHED = :matched
  # Input matches to a key sequence and the key sequence is a prefix of another key sequence
  MATCHING_MATCHED = :matching_matched
  # Input does not match to any key sequence
  UNMATCHED = :unmatched

  def match_status(input)
    matching = key_mapping.matching?(input)
    matched = key_mapping.get(input)

    # FIXME: Workaround for single byte. remove this after MAPPING is merged into KeyActor.
    matched ||= input.size == 1
    matching ||= input == [ESC_BYTE]

    if matching && matched
      MATCHING_MATCHED
    elsif matching
      MATCHING
    elsif matched
      MATCHED
    elsif input[0] == ESC_BYTE
      match_unknown_escape_sequence(input, vi_mode: @config.editing_mode_is?(:vi_insert, :vi_command))
    elsif input.size == 1
      MATCHED
    else
      UNMATCHED
    end
  end

  def expand(input)
    matched_bytes = nil
    (1..input.size).each do |i|
      bytes = input.take(i)
      status = match_status(bytes)
      matched_bytes = bytes if status == MATCHED || status == MATCHING_MATCHED
    end
    return [[], []] unless matched_bytes

    func = key_mapping.get(matched_bytes)
    if func.is_a?(Array)
      keys = func.map { |c| Reline::Key.new(c, c, false) }
    elsif func
      keys = [Reline::Key.new(func, func, false)]
    elsif matched_bytes.size == 1
      keys = [Reline::Key.new(matched_bytes.first, matched_bytes.first, false)]
    elsif matched_bytes.size == 2 && matched_bytes[0] == ESC_BYTE
      keys = [Reline::Key.new(matched_bytes[1], matched_bytes[1] | 0b10000000, true)]
    else
      keys = []
    end

    [keys, input.drop(matched_bytes.size)]
  end

  private

  # returns match status of CSI/SS3 sequence and matched length
  def match_unknown_escape_sequence(input, vi_mode: false)
    idx = 0
    return UNMATCHED unless input[idx] == ESC_BYTE
    idx += 1
    idx += 1 if input[idx] == ESC_BYTE

    case input[idx]
    when nil
      if idx == 1 # `ESC`
        return MATCHING_MATCHED
      else # `ESC ESC`
        return MATCHING
      end
    when 91 # == '['.ord
      # CSI sequence `ESC [ ... char`
      idx += 1
      idx += 1 while idx < input.size && CSI_PARAMETER_BYTES_RANGE.cover?(input[idx])
      idx += 1 while idx < input.size && CSI_INTERMEDIATE_BYTES_RANGE.cover?(input[idx])
    when 79 # == 'O'.ord
      # SS3 sequence `ESC O char`
      idx += 1
    else
      # `ESC char` or `ESC ESC char`
      return UNMATCHED if vi_mode
    end

    case input.size
    when idx
      MATCHING
    when idx + 1
      MATCHED
    else
      UNMATCHED
    end
  end

  def key_mapping
    @config.key_bindings
  end
end
