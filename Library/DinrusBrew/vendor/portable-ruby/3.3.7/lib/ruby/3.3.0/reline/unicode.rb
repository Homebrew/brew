class Reline::Unicode
  EscapedPairs = {
    0x00 => '^@',
    0x01 => '^A', # C-a
    0x02 => '^B',
    0x03 => '^C',
    0x04 => '^D',
    0x05 => '^E',
    0x06 => '^F',
    0x07 => '^G',
    0x08 => '^H', # Backspace
    0x09 => '^I',
    0x0A => '^J',
    0x0B => '^K',
    0x0C => '^L',
    0x0D => '^M', # Enter
    0x0E => '^N',
    0x0F => '^O',
    0x10 => '^P',
    0x11 => '^Q',
    0x12 => '^R',
    0x13 => '^S',
    0x14 => '^T',
    0x15 => '^U',
    0x16 => '^V',
    0x17 => '^W',
    0x18 => '^X',
    0x19 => '^Y',
    0x1A => '^Z', # C-z
    0x1B => '^[', # C-[ C-3
    0x1D => '^]', # C-]
    0x1E => '^^', # C-~ C-6
    0x1F => '^_', # C-_ C-7
    0x7F => '^?', # C-? C-8
  }
  EscapedChars = EscapedPairs.keys.map(&:chr)

  NON_PRINTING_START = "\1"
  NON_PRINTING_END = "\2"
  CSI_REGEXP = /\e\[[\d;]*[ABCDEFGHJKSTfminsuhl]/
  OSC_REGEXP = /\e\]\d+(?:;[^;\a\e]+)*(?:\a|\e\\)/
  WIDTH_SCANNER = /\G(?:(#{NON_PRINTING_START})|(#{NON_PRINTING_END})|(#{CSI_REGEXP})|(#{OSC_REGEXP})|(\X))/o

  def self.escape_for_print(str)
    str.chars.map! { |gr|
      case gr
      when -"\n"
        gr
      when -"\t"
        -'  '
      else
        EscapedPairs[gr.ord] || gr
      end
    }.join
  end

  require 'reline/unicode/east_asian_width'

  def self.get_mbchar_width(mbchar)
    ord = mbchar.ord
    if ord <= 0x1F # in EscapedPairs
      return 2
    elsif ord <= 0x7E # printable ASCII chars
      return 1
    end
    utf8_mbchar = mbchar.encode(Encoding::UTF_8)
    ord = utf8_mbchar.ord
    chunk_index = EastAsianWidth::CHUNK_LAST.bsearch_index { |o| ord <= o }
    size = EastAsianWidth::CHUNK_WIDTH[chunk_index]
    if size == -1
      Reline.ambiguous_width
    elsif size == 1 && utf8_mbchar.size >= 2
      second_char_ord = utf8_mbchar[1].ord
      # Halfwidth Dakuten Handakuten
      # Only these two character has Letter Modifier category and can be combined in a single grapheme cluster
      (second_char_ord == 0xFF9E || second_char_ord == 0xFF9F) ? 2 : 1
    else
      size
    end
  end

  def self.calculate_width(str, allow_escape_code = false)
    if allow_escape_code
      width = 0
      rest = str.encode(Encoding::UTF_8)
      in_zero_width = false
      rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
        case
        when non_printing_start
          in_zero_width = true
        when non_printing_end
          in_zero_width = false
        when csi, osc
        when gc
          unless in_zero_width
            width += get_mbchar_width(gc)
          end
        end
      end
      width
    else
      str.encode(Encoding::UTF_8).grapheme_clusters.inject(0) { |w, gc|
        w + get_mbchar_width(gc)
      }
    end
  end

  def self.split_by_width(str, max_width, encoding = str.encoding, offset: 0)
    lines = [String.new(encoding: encoding)]
    height = 1
    width = offset
    rest = str.encode(Encoding::UTF_8)
    in_zero_width = false
    seq = String.new(encoding: encoding)
    rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
      case
      when non_printing_start
        in_zero_width = true
        lines.last << NON_PRINTING_START
      when non_printing_end
        in_zero_width = false
        lines.last << NON_PRINTING_END
      when csi
        lines.last << csi
        unless in_zero_width
          if csi == -"\e[m" || csi == -"\e[0m"
            seq.clear
          else
            seq << csi
          end
        end
      when osc
        lines.last << osc
        seq << osc
      when gc
        unless in_zero_width
          mbchar_width = get_mbchar_width(gc)
          if (width += mbchar_width) > max_width
            width = mbchar_width
            lines << nil
            lines << seq.dup
            height += 1
          end
        end
        lines.last << gc
      end
    end
    # The cursor moves to next line in first
    if width == max_width
      lines << nil
      lines << String.new(encoding: encoding)
      height += 1
    end
    [lines, height]
  end

  # Take a chunk of a String cut by width with escape sequences.
  def self.take_range(str, start_col, max_width)
    take_mbchar_range(str, start_col, max_width).first
  end

  def self.take_mbchar_range(str, start_col, width, cover_begin: false, cover_end: false, padding: false)
    chunk = String.new(encoding: str.encoding)

    end_col = start_col + width
    total_width = 0
    rest = str.encode(Encoding::UTF_8)
    in_zero_width = false
    chunk_start_col = nil
    chunk_end_col = nil
    has_csi = false
    rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
      case
      when non_printing_start
        in_zero_width = true
        chunk << NON_PRINTING_START
      when non_printing_end
        in_zero_width = false
        chunk << NON_PRINTING_END
      when csi
        has_csi = true
        chunk << csi
      when osc
        chunk << osc
      when gc
        if in_zero_width
          chunk << gc
          next
        end

        mbchar_width = get_mbchar_width(gc)
        prev_width = total_width
        total_width += mbchar_width

        if (cover_begin || padding ? total_width <= start_col : prev_width < start_col)
          # Current character haven't reached start_col yet
          next
        elsif padding && !cover_begin && prev_width < start_col && start_col < total_width
          # Add preceding padding. This padding might have background color.
          chunk << ' '
          chunk_start_col ||= start_col
          chunk_end_col = total_width
          next
        elsif (cover_end ? prev_width < end_col : total_width <= end_col)
          # Current character is in the range
          chunk << gc
          chunk_start_col ||= prev_width
          chunk_end_col = total_width
          break if total_width >= end_col
        else
          # Current character exceeds end_col
          if padding && end_col < total_width
            # Add succeeding padding. This padding might have background color.
            chunk << ' '
            chunk_start_col ||= prev_width
            chunk_end_col = end_col
          end
          break
        end
      end
    end
    chunk_start_col ||= start_col
    chunk_end_col ||= start_col
    if padding && chunk_end_col < end_col
      # Append padding. This padding should not include background color.
      chunk << "\e[0m" if has_csi
      chunk << ' ' * (end_col - chunk_end_col)
      chunk_end_col = end_col
    end
    [chunk, chunk_start_col, chunk_end_col - chunk_start_col]
  end

  def self.get_next_mbchar_size(line, byte_pointer)
    grapheme = line.byteslice(byte_pointer..-1).grapheme_clusters.first
    grapheme ? grapheme.bytesize : 0
  end

  def self.get_prev_mbchar_size(line, byte_pointer)
    if byte_pointer.zero?
      0
    else
      grapheme = line.byteslice(0..(byte_pointer - 1)).grapheme_clusters.last
      grapheme ? grapheme.bytesize : 0
    end
  end

  def self.em_forward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.em_forward_word_with_capitalization(line, byte_pointer)
    width = 0
    byte_size = 0
    new_str = String.new
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      new_str += mbchar
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    first = true
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      if first
        new_str += mbchar.upcase
        first = false
      else
        new_str += mbchar.downcase
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width, new_str]
  end

  def self.em_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.em_big_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.ed_transpose_words(line, byte_pointer)
    right_word_start = nil
    size = get_next_mbchar_size(line, byte_pointer)
    mbchar = line.byteslice(byte_pointer, size)
    if size.zero?
      # ' aaa bbb [cursor]'
      byte_size = 0
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
        byte_size -= size
      end
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size -= size
      end
      right_word_start = byte_pointer + byte_size
      byte_size = 0
      while line.bytesize > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size += size
      end
      after_start = byte_pointer + byte_size
    elsif mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      # ' aaa bb[cursor]b'
      byte_size = 0
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size -= size
      end
      right_word_start = byte_pointer + byte_size
      byte_size = 0
      while line.bytesize > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size += size
      end
      after_start = byte_pointer + byte_size
    else
      byte_size = 0
      while (line.bytesize - 1) > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
        byte_size += size
      end
      if (byte_pointer + byte_size) == (line.bytesize - 1)
        # ' aaa bbb [cursor] '
        after_start = line.bytesize
        while 0 < (byte_pointer + byte_size)
          size = get_prev_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size - size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
          byte_size -= size
        end
        while 0 < (byte_pointer + byte_size)
          size = get_prev_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size - size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
          byte_size -= size
        end
        right_word_start = byte_pointer + byte_size
      else
        # ' aaa [cursor] bbb '
        right_word_start = byte_pointer + byte_size
        while line.bytesize > (byte_pointer + byte_size)
          size = get_next_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
          byte_size += size
        end
        after_start = byte_pointer + byte_size
      end
    end
    byte_size = right_word_start - byte_pointer
    while 0 < (byte_pointer + byte_size)
      size = get_prev_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      byte_size -= size
    end
    middle_start = byte_pointer + byte_size
    byte_size = middle_start - byte_pointer
    while 0 < (byte_pointer + byte_size)
      size = get_prev_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      byte_size -= size
    end
    left_word_start = byte_pointer + byte_size
    [left_word_start, middle_start, right_word_start, after_start]
  end

  def self.vi_big_forward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_big_forward_end_word(line, byte_pointer)
    if (line.bytesize - 1) > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    prev_width = width
    prev_byte_size = byte_size
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\s/
      prev_width = width
      prev_byte_size = byte_size
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [prev_byte_size, prev_width]
  end

  def self.vi_big_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_forward_word(line, byte_pointer, drop_terminate_spaces = false)
    if line.bytesize > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      if mbchar =~ /\w/
        started_by = :word
      elsif mbchar =~ /\s/
        started_by = :space
      else
        started_by = :non_word_printable
      end
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :space
        break if mbchar =~ /\S/
      when :non_word_printable
        break if mbchar =~ /\w|\s/
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    return [byte_size, width] if drop_terminate_spaces
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_forward_end_word(line, byte_pointer)
    if (line.bytesize - 1) > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      if mbchar =~ /\w/
        started_by = :word
      elsif mbchar =~ /\s/
        started_by = :space
      else
        started_by = :non_word_printable
      end
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    if (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      if mbchar =~ /\w/
        second = :word
      elsif mbchar =~ /\s/
        second = :space
      else
        second = :non_word_printable
      end
      second_width = get_mbchar_width(mbchar)
      second_byte_size = size
    else
      return [byte_size, width]
    end
    if second == :space
      width += second_width
      byte_size += second_byte_size
      while (line.bytesize - 1) > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        if mbchar =~ /\S/
          if mbchar =~ /\w/
            started_by = :word
          else
            started_by = :non_word_printable
          end
          break
        end
        width += get_mbchar_width(mbchar)
        byte_size += size
      end
    else
      case [started_by, second]
      when [:word, :non_word_printable], [:non_word_printable, :word]
        started_by = second
      else
        width += second_width
        byte_size += second_byte_size
        started_by = second
      end
    end
    prev_width = width
    prev_byte_size = byte_size
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :non_word_printable
        break if mbchar =~ /[\w\s]/
      end
      prev_width = width
      prev_byte_size = byte_size
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [prev_byte_size, prev_width]
  end

  def self.vi_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      if mbchar =~ /\S/
        if mbchar =~ /\w/
          started_by = :word
        else
          started_by = :non_word_printable
        end
        break
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :non_word_printable
        break if mbchar =~ /[\w\s]/
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_first_print(line)
    width = 0
    byte_size = 0
    while (line.bytesize - 1) > byte_size
      size = get_next_mbchar_size(line, byte_size)
      mbchar = line.byteslice(byte_size, size)
      if mbchar =~ /\S/
        break
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end
end
