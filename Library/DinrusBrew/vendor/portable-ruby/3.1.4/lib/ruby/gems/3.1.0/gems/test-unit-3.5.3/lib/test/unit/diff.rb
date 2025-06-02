# port of Python's difflib.
#
# Copyright (c) 2001-2008 Python Software Foundation; All Rights Reserved
# Copyright (c) 2008-2011 Kouhei Sutou; All Rights Reserved
#
# It is free software, and is distributed under (the new Ruby license
# or BSDL) and the PSF license.

module Test
  module Unit
    module Diff
      class SequenceMatcher
        def initialize(from, to, &junk_predicate)
          @from = from
          @to = to
          @junk_predicate = junk_predicate
          update_to_indexes
        end

        def longest_match(from_start, from_end, to_start, to_end)
          best_info = find_best_match_position(from_start, from_end,
                                               to_start, to_end)
          unless @junks.empty?
            args = [from_start, from_end, to_start, to_end]
            best_info = adjust_best_info_with_junk_predicate(false, best_info,
                                                             *args)
            best_info = adjust_best_info_with_junk_predicate(true, best_info,
                                                             *args)
          end

          best_info
        end

        def blocks
          @blocks ||= compute_blocks
        end

        def operations
          @operations ||= compute_operations
        end

        def grouped_operations(context_size=nil)
          context_size ||= 3
          _operations = operations.dup
          _operations = [[:equal, 0, 0, 0, 0]] if _operations.empty?
          expand_edge_equal_operations!(_operations, context_size)

          group_window = context_size * 2
          groups = []
          group = []
          _operations.each do |tag, from_start, from_end, to_start, to_end|
            if tag == :equal and from_end - from_start > group_window
              group << [tag,
                        from_start,
                        [from_end, from_start + context_size].min,
                        to_start,
                        [to_end, to_start + context_size].min]
              groups << group
              group = []
              from_start = [from_start, from_end - context_size].max
              to_start = [to_start, to_end - context_size].max
            end
            group << [tag, from_start, from_end, to_start, to_end]
          end
          groups << group unless group.empty?
          groups
        end

        def ratio
          @ratio ||= compute_ratio
        end

        private
        def update_to_indexes
          @to_indexes = {}
          @junks = {}
          if @to.is_a?(String)
            each = " "[0].is_a?(Integer) ? :each_byte : :each_char
          else
            each = :each
          end
          i = 0
          @to.__send__(each) do |item|
            @to_indexes[item] ||= []
            @to_indexes[item] << i
            i += 1
          end

          return if @junk_predicate.nil?
          @to_indexes = @to_indexes.reject do |key, value|
            junk = @junk_predicate.call(key)
            @junks[key] = true if junk
            junk
          end
        end

        def find_best_match_position(from_start, from_end, to_start, to_end)
          best_from, best_to, best_size = from_start, to_start, 0
          sizes = {}
          from_start.upto(from_end) do |from_index|
            _sizes = {}
            (@to_indexes[@from[from_index]] || []).each do |to_index|
              next if to_index < to_start
              break if to_index > to_end
              size = _sizes[to_index] = (sizes[to_index - 1] || 0) + 1
              if size > best_size
                best_from = from_index - size + 1
                best_to = to_index - size + 1
                best_size = size
              end
            end
            sizes = _sizes
          end
          [best_from, best_to, best_size]
        end

        def adjust_best_info_with_junk_predicate(should_junk, best_info,
                                                 from_start, from_end,
                                                 to_start, to_end)
          best_from, best_to, best_size = best_info
          while best_from > from_start and best_to > to_start and
              (should_junk ?
               @junks.has_key?(@to[best_to - 1]) :
               !@junks.has_key?(@to[best_to - 1])) and
              @from[best_from - 1] == @to[best_to - 1]
            best_from -= 1
            best_to -= 1
            best_size += 1
          end

          while best_from + best_size < from_end and
              best_to + best_size < to_end and
              (should_junk ?
               @junks.has_key?(@to[best_to + best_size]) :
               !@junks.has_key?(@to[best_to + best_size])) and
              @from[best_from + best_size] == @to[best_to + best_size]
            best_size += 1
          end

          [best_from, best_to, best_size]
        end

        def matches
          @matches ||= compute_matches
        end

        def compute_matches
          matches = []
          queue = [[0, @from.size, 0, @to.size]]
          until queue.empty?
            from_start, from_end, to_start, to_end = queue.pop
            match = longest_match(from_start, from_end - 1, to_start, to_end - 1)
            match_from_index, match_to_index, size = match
            unless size.zero?
              if from_start < match_from_index and
                  to_start < match_to_index
                queue.push([from_start, match_from_index,
                            to_start, match_to_index])
              end
              matches << match
              if match_from_index + size < from_end and
                  match_to_index + size < to_end
                queue.push([match_from_index + size, from_end,
                            match_to_index + size, to_end])
              end
            end
          end
          matches.sort_by do |(from_index, _, _)|
            from_index
          end
        end

        def compute_blocks
          blocks = []
          current_from_index = current_to_index = current_size = 0
          matches.each do |from_index, to_index, size|
            if current_from_index + current_size == from_index and
                current_to_index + current_size == to_index
              current_size += size
            else
              unless current_size.zero?
                blocks << [current_from_index, current_to_index, current_size]
              end
              current_from_index = from_index
              current_to_index = to_index
              current_size = size
            end
          end
          unless current_size.zero?
            blocks << [current_from_index, current_to_index, current_size]
          end

          blocks << [@from.size, @to.size, 0]
          blocks
        end

        def compute_operations
          from_index = to_index = 0
          operations = []
          blocks.each do |match_from_index, match_to_index, size|
            tag = determine_tag(from_index, to_index,
                                match_from_index, match_to_index)
            if tag != :equal
              operations << [tag,
                             from_index, match_from_index,
                             to_index, match_to_index]
            end

            from_index, to_index = match_from_index + size, match_to_index + size
            if size > 0
              operations << [:equal,
                             match_from_index, from_index,
                             match_to_index, to_index]
            end
          end
          operations
        end

        def compute_ratio
          matches = blocks.inject(0) {|result, block| result + block[-1]}
          length = @from.length + @to.length
          if length.zero?
            1.0
          else
            2.0 * matches / length
          end
        end

        def determine_tag(from_index, to_index,
                          match_from_index, match_to_index)
          if from_index < match_from_index and to_index < match_to_index
            :replace
          elsif from_index < match_from_index
            :delete
          elsif to_index < match_to_index
            :insert
          else
            :equal
          end
        end

        def expand_edge_equal_operations!(_operations, context_size)
          tag, from_start, from_end, to_start, to_end = _operations[0]
          if tag == :equal
            _operations[0] = [tag,
                              [from_start, from_end - context_size].max,
                              from_end,
                              [to_start, to_end - context_size].max,
                              to_end]
          end

          tag, from_start, from_end, to_start, to_end = _operations[-1]
          if tag == :equal
            _operations[-1] = [tag,
                               from_start,
                               [from_end, from_start + context_size].min,
                               to_start,
                               [to_end, to_start + context_size].min]
          end
        end
      end

      class Differ
        def initialize(from, to)
          @from = from
          @to = to
        end

        private
        def tag(mark, contents)
          contents.collect {|content| mark + content}
        end
      end

      class UTF8Line
        class << self
          # from http://unicode.org/reports/tr11/
          WIDE_CHARACTERS =
            [0x1100..0x1159, 0x115F..0x115F, 0x2329..0x232A,
             0x2E80..0x2E99, 0x2E9B..0x2EF3, 0x2F00..0x2FD5,
             0x2FF0..0x2FFB, 0x3000..0x303E, 0x3041..0x3096,
             0x3099..0x30FF, 0x3105..0x312D, 0x3131..0x318E,
             0x3190..0x31B7, 0x31C0..0x31E3, 0x31F0..0x321E,
             0x3220..0x3243, 0x3250..0x32FE, 0x3300..0x4DB5,
             0x4E00..0x9FC3, 0xA000..0xA48C, 0xA490..0xA4C6,
             0xAC00..0xD7A3, 0xF900..0xFA2D, 0xFA30..0xFA6A,
             0xFA70..0xFAD9, 0xFE10..0xFE19, 0xFE30..0xFE52,
             0xFE54..0xFE66, 0xFE68..0xFE6B, 0xFF01..0xFF60,
             0xFFE0..0xFFE6, 0x20000..0x2FFFD, 0x30000..0x3FFFD,
            ]

          AMBIGUOUS =
            [0x00A1..0x00A1, 0x00A4..0x00A4, 0x00A7..0x00A8,
             0x00AA..0x00AA, 0x00AD..0x00AE, 0x00B0..0x00B4,
             0x00B6..0x00BA, 0x00BC..0x00BF, 0x00C6..0x00C6,
             0x00D0..0x00D0, 0x00D7..0x00D8, 0x00DE..0x00E1,
             0x00E6..0x00E6, 0x00E8..0x00EA, 0x00EC..0x00ED,
             0x00F0..0x00F0, 0x00F2..0x00F3, 0x00F7..0x00FA,
             0x00FC..0x00FC, 0x00FE..0x00FE, 0x0101..0x0101,
             0x0111..0x0111, 0x0113..0x0113, 0x011B..0x011B,
             0x0126..0x0127, 0x012B..0x012B, 0x0131..0x0133,
             0x0138..0x0138, 0x013F..0x0142, 0x0144..0x0144,
             0x0148..0x014B, 0x014D..0x014D, 0x0152..0x0153,
             0x0166..0x0167, 0x016B..0x016B, 0x01CE..0x01CE,
             0x01D0..0x01D0, 0x01D2..0x01D2, 0x01D4..0x01D4,
             0x01D6..0x01D6, 0x01D8..0x01D8, 0x01DA..0x01DA,
             0x01DC..0x01DC, 0x0251..0x0251, 0x0261..0x0261,
             0x02C4..0x02C4, 0x02C7..0x02C7, 0x02C9..0x02CB,
             0x02CD..0x02CD, 0x02D0..0x02D0, 0x02D8..0x02DB,
             0x02DD..0x02DD, 0x02DF..0x02DF, 0x0300..0x036F,
             0x0391..0x03A1, 0x03A3..0x03A9, 0x03B1..0x03C1,
             0x03C3..0x03C9, 0x0401..0x0401, 0x0410..0x044F,
             0x0451..0x0451, 0x2010..0x2010, 0x2013..0x2016,
             0x2018..0x2019, 0x201C..0x201D, 0x2020..0x2022,
             0x2024..0x2027, 0x2030..0x2030, 0x2032..0x2033,
             0x2035..0x2035, 0x203B..0x203B, 0x203E..0x203E,
             0x2074..0x2074, 0x207F..0x207F, 0x2081..0x2084,
             0x20AC..0x20AC, 0x2103..0x2103, 0x2105..0x2105,
             0x2109..0x2109, 0x2113..0x2113, 0x2116..0x2116,
             0x2121..0x2122, 0x2126..0x2126, 0x212B..0x212B,
             0x2153..0x2154, 0x215B..0x215E, 0x2160..0x216B,
             0x2170..0x2179, 0x2190..0x2199, 0x21B8..0x21B9,
             0x21D2..0x21D2, 0x21D4..0x21D4, 0x21E7..0x21E7,
             0x2200..0x2200, 0x2202..0x2203, 0x2207..0x2208,
             0x220B..0x220B, 0x220F..0x220F, 0x2211..0x2211,
             0x2215..0x2215, 0x221A..0x221A, 0x221D..0x2220,
             0x2223..0x2223, 0x2225..0x2225, 0x2227..0x222C,
             0x222E..0x222E, 0x2234..0x2237, 0x223C..0x223D,
             0x2248..0x2248, 0x224C..0x224C, 0x2252..0x2252,
             0x2260..0x2261, 0x2264..0x2267, 0x226A..0x226B,
             0x226E..0x226F, 0x2282..0x2283, 0x2286..0x2287,
             0x2295..0x2295, 0x2299..0x2299, 0x22A5..0x22A5,
             0x22BF..0x22BF, 0x2312..0x2312, 0x2460..0x24E9,
             0x24EB..0x254B, 0x2550..0x2573, 0x2580..0x258F,
             0x2592..0x2595, 0x25A0..0x25A1, 0x25A3..0x25A9,
             0x25B2..0x25B3, 0x25B6..0x25B7, 0x25BC..0x25BD,
             0x25C0..0x25C1, 0x25C6..0x25C8, 0x25CB..0x25CB,
             0x25CE..0x25D1, 0x25E2..0x25E5, 0x25EF..0x25EF,
             0x2605..0x2606, 0x2609..0x2609, 0x260E..0x260F,
             0x2614..0x2615, 0x261C..0x261C, 0x261E..0x261E,
             0x2640..0x2640, 0x2642..0x2642, 0x2660..0x2661,
             0x2663..0x2665, 0x2667..0x266A, 0x266C..0x266D,
             0x266F..0x266F, 0x273D..0x273D, 0x2776..0x277F,
             0xE000..0xF8FF, 0xFE00..0xFE0F, 0xFFFD..0xFFFD,
             0xE0100..0xE01EF, 0xF0000..0xFFFFD, 0x100000..0x10FFFD,
            ]

          def wide_character?(character)
            binary_search_ranges(character, WIDE_CHARACTERS) or
              binary_search_ranges(character, AMBIGUOUS)
          end

          private
          def binary_search_ranges(character, ranges)
            if ranges.size.zero?
              false
            elsif ranges.size == 1
              ranges[0].include?(character)
            else
              half = ranges.size / 2
              range = ranges[half]
              if range.include?(character)
                true
              elsif character < range.begin
                binary_search_ranges(character, ranges[0...half])
              else
                binary_search_ranges(character, ranges[(half + 1)..-1])
              end
            end
          end
        end

        def initialize(line)
          @line = line
          @characters = @line.unpack("U*")
        end

        def [](*args)
          result = @characters[*args]
          if result.respond_to?(:pack)
            result.pack("U*")
          else
            result
          end
        end

        def each(&block)
          @characters.each(&block)
        end

        def size
          @characters.size
        end

        def to_s
          @line
        end

        def compute_width(start, _end)
          width = 0
          start.upto(_end - 1) do |i|
            if self.class.wide_character?(@characters[i])
              width += 2
            else
              width += 1
            end
          end
          width
        end
      end

      class ReadableDiffer < Differ
        def diff(options={})
          @result = []
          operations.each do |tag, from_start, from_end, to_start, to_end|
            case tag
            when :replace
              diff_lines(from_start, from_end, to_start, to_end)
            when :delete
              tag_deleted(@from[from_start...from_end])
            when :insert
              tag_inserted(@to[to_start...to_end])
            when :equal
              tag_equal(@from[from_start...from_end])
            else
              raise "unknown tag: #{tag}"
            end
          end
          @result
        end

        private
        def operations
          @operations ||= nil
          if @operations.nil?
            matcher = SequenceMatcher.new(@from, @to)
            @operations = matcher.operations
          end
          @operations
        end

        def default_ratio
          0.74
        end

        def cut_off_ratio
          0.75
        end

        def tag(mark, contents)
          contents.each do |content|
            @result << (mark + content)
          end
        end

        def tag_deleted(contents)
          tag("- ", contents)
        end

        def tag_inserted(contents)
          tag("+ ", contents)
        end

        def tag_equal(contents)
          tag("  ", contents)
        end

        def tag_difference(contents)
          tag("? ", contents)
        end

        def find_diff_line_info(from_start, from_end, to_start, to_end)
          best_ratio = default_ratio
          from_equal_index = to_equal_index = nil
          from_best_index = to_best_index = nil

          to_start.upto(to_end - 1) do |to_index|
            from_start.upto(from_end - 1) do |from_index|
              if @from[from_index] == @to[to_index]
                from_equal_index ||= from_index
                to_equal_index ||= to_index
                next
              end

              matcher = SequenceMatcher.new(@from[from_index], @to[to_index],
                                            &method(:space_character?))
              if matcher.ratio > best_ratio
                best_ratio = matcher.ratio
                from_best_index = from_index
                to_best_index = to_index
              end
            end
          end

          [best_ratio,
           from_equal_index, to_equal_index,
           from_best_index,  to_best_index]
        end

        def diff_lines(from_start, from_end, to_start, to_end)
          info = find_diff_line_info(from_start, from_end, to_start, to_end)
          best_ratio, from_equal_index, to_equal_index, *info = info
          from_best_index, to_best_index = info
          from_best_index ||= from_start
          to_best_index ||= to_start

          if best_ratio < cut_off_ratio
            if from_equal_index.nil?
              if to_end - to_start < from_end - from_start
                tag_inserted(@to[to_start...to_end])
                tag_deleted(@from[from_start...from_end])
              else
                tag_deleted(@from[from_start...from_end])
                tag_inserted(@to[to_start...to_end])
              end
              return
            end
            from_best_index = from_equal_index
            to_best_index = to_equal_index
            best_ratio = 1.0
          end

          _diff_lines(from_start, from_best_index, to_start, to_best_index)
          diff_line(@from[from_best_index], @to[to_best_index])
          _diff_lines(from_best_index + 1, from_end, to_best_index + 1, to_end)
        end

        def _diff_lines(from_start, from_end, to_start, to_end)
          if from_start < from_end
            if to_start < to_end
              diff_lines(from_start, from_end, to_start, to_end)
            else
              tag_deleted(@from[from_start...from_end])
            end
          else
            tag_inserted(@to[to_start...to_end])
          end
        end

        def line_operations(from_line, to_line)
          if !from_line.respond_to?(:force_encoding) and $KCODE == "UTF8"
            from_line = UTF8Line.new(from_line)
            to_line = UTF8Line.new(to_line)
          end
          matcher = SequenceMatcher.new(from_line, to_line,
                                        &method(:space_character?))
          [from_line, to_line, matcher.operations]
        end

        def compute_width(line, start, _end)
          if line.respond_to?(:encoding) and
              Encoding.compatible?(Encoding::UTF_8, line.encoding)
            utf8_line = line[start..._end].encode(Encoding::UTF_8)
            width = 0
            utf8_line.each_codepoint do |unicode_codepoint|
              if UTF8Line.wide_character?(unicode_codepoint)
                width += 2
              else
                width += 1
              end
            end
            width
          elsif line.is_a?(UTF8Line)
            line.compute_width(start, _end)
          else
            _end - start
          end
        end

        def diff_line(from_line, to_line)
          from_tags = ""
          to_tags = ""
          from_line, to_line, _operations = line_operations(from_line, to_line)
          _operations.each do |tag, from_start, from_end, to_start, to_end|
            from_width = compute_width(from_line, from_start, from_end)
            to_width = compute_width(to_line, to_start, to_end)
            case tag
            when :replace
              from_tags += "^" * from_width
              to_tags += "^" * to_width
            when :delete
              from_tags += "-" * from_width
            when :insert
              to_tags += "+" * to_width
            when :equal
              from_tags += " " * from_width
              to_tags += " " * to_width
            else
              raise "unknown tag: #{tag}"
            end
          end
          format_diff_point(from_line, to_line, from_tags, to_tags)
        end

        def format_diff_point(from_line, to_line, from_tags, to_tags)
          common = [n_leading_characters(from_line, ?\t),
                    n_leading_characters(to_line, ?\t)].min
          common = [common,
                    n_leading_characters(from_tags[0, common], " "[0])].min
          from_tags = from_tags[common..-1].rstrip
          to_tags = to_tags[common..-1].rstrip

          tag_deleted([from_line])
          unless from_tags.empty?
            tag_difference(["#{"\t" * common}#{from_tags}"])
          end
          tag_inserted([to_line])
          unless to_tags.empty?
            tag_difference(["#{"\t" * common}#{to_tags}"])
          end
        end

        def n_leading_characters(string, character)
          n = 0
          while string[n] == character
            n += 1
          end
          n
        end

        def space_character?(character)
          [" "[0], "\t"[0]].include?(character)
        end
      end

      class UnifiedDiffer < Differ
        def diff(options={})
          groups = SequenceMatcher.new(@from, @to).grouped_operations
          return [] if groups.empty?
          return [] if same_content?(groups)

          show_context = options[:show_context]
          show_context = true if show_context.nil?
          result = ["--- #{options[:from_label]}".rstrip,
                    "+++ #{options[:to_label]}".rstrip]
          groups.each do |operations|
            result << format_summary(operations, show_context)
            operations.each do |args|
              operation_tag, from_start, from_end, to_start, to_end = args
              case operation_tag
              when :replace
                result.concat(tag("-", @from[from_start...from_end]))
                result.concat(tag("+", @to[to_start...to_end]))
              when :delete
                result.concat(tag("-", @from[from_start...from_end]))
              when :insert
                result.concat(tag("+", @to[to_start...to_end]))
              when :equal
                result.concat(tag(" ", @from[from_start...from_end]))
              end
            end
          end
          result
        end

        private
        def same_content?(groups)
          return false if groups.size != 1
          group = groups[0]
          return false if group.size != 1
          tag, from_start, from_end, to_start, to_end = group[0]

          tag == :equal and [from_start, from_end] == [to_start, to_end]
        end

        def format_summary(operations, show_context)
          _, first_from_start, _, first_to_start, _ = operations[0]
          _, _, last_from_end, _, last_to_end = operations[-1]
          summary = "@@ -%d,%d +%d,%d @@" % [first_from_start + 1,
                                             last_from_end - first_from_start,
                                             first_to_start + 1,
                                             last_to_end - first_to_start,]
          if show_context
            interesting_line = find_interesting_line(first_from_start,
                                                     first_to_start,
                                                     :define_line?)
            summary << " #{interesting_line}" if interesting_line
          end
          summary
        end

        def find_interesting_line(from_start, to_start, predicate)
          from_index = from_start
          to_index = to_start
          while from_index >= 0 or to_index >= 0
            [@from[from_index], @to[to_index]].each do |line|
              return line if line and __send__(predicate, line)
            end

            from_index -= 1
            to_index -= 1
          end
          nil
        end

        def define_line?(line)
          /\A(?:[_a-zA-Z$]|\s*(?:class|module|def)\b)/ =~ line
        end
      end

      module_function
      def need_fold?(diff)
        /^[-+].{79}/ =~ diff
      end

      def fold(string)
        string.split(/\r?\n/).collect do |line|
          line.gsub(/(.{78})/, "\\1\n")
        end.join("\n")
      end

      def folded_readable(from, to, options={})
        readable(fold(from), fold(to), options)
      end

      def readable(from, to, options={})
        diff(ReadableDiffer, from, to, options)
      end

      def unified(from, to, options={})
        diff(UnifiedDiffer, from, to, options)
      end

      def diff(differ_class, from, to, options={})
        if from.respond_to?(:valid_encoding?) and not from.valid_encoding?
          from = from.dup.force_encoding("ASCII-8BIT")
        end
        if to.respond_to?(:valid_encoding?) and not to.valid_encoding?
          to = to.dup.force_encoding("ASCII-8BIT")
        end
        differ = differ_class.new(from.split(/\r?\n/), to.split(/\r?\n/))
        lines = differ.diff(options)
        if Object.const_defined?(:EncodingError)
          begin
            lines.join("\n")
          rescue EncodingError
            lines.collect {|line| line.force_encoding("ASCII-8BIT")}.join("\n")
          end
        else
          lines.join("\n")
        end
      end
    end
  end
end
