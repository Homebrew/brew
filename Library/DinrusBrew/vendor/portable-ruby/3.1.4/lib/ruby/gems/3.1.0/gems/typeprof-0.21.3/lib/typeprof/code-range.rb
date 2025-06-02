module TypeProf
  class CodeLocation
    # In Ruby, lineno is 1-origin, and column is 0-origin
    def initialize(lineno, column)
      @lineno = lineno
      @column = column
    end

    def inspect
      "(%d,%d)" % [@lineno, @column]
    end

    attr_reader :lineno, :column

    def self.from_lsp(lsp_loc)
      # In the Language Server Protocol, lineno and column are both 0-origin
      CodeLocation.new(lsp_loc[:line] + 1, lsp_loc[:character])
    end

    def to_lsp
      { line: @lineno - 1, character: @column }
    end

    def advance_cursor(offset, source_text)
      new_lineno = @lineno
      new_column = @column
      while offset > 0
        line_text = source_text.lines[new_lineno - 1]
        if new_column + offset >= line_text.length
          advanced = line_text.length - new_column
          offset -= advanced
          new_lineno += 1
          new_column = 0
        else
          new_column += offset
          break
        end
      end
      CodeLocation.new(new_lineno, new_column)
    end

    def <=>(other)
      ret = @lineno <=> other.lineno
      return ret if ret != 0
      @column <=> other.column
    end

    include Comparable
  end

  class CodeRange
    def initialize(first, last)
      @first, @last = first, last
    end

    def inspect
      "%p-%p" % [@first, @last]
    end

    attr_reader :first
    attr_reader :last

    def self.from_lsp(lsp_range)
      CodeRange.new(CodeLocation.from_lsp(lsp[:start]), CodeLocation.from_lsp(lsp[:end]))
    end

    def self.from_rbs(rbs_loc)
      CodeRange.new(
        CodeLocation.new(rbs_loc.start_line, rbs_loc.start_column),
        CodeLocation.new(rbs_loc.end_line, rbs_loc.end_column),
      )
    end

    def to_lsp
      { start: @first.to_lsp, end: @last.to_lsp }
    end

    def contain_loc?(loc)
      @first <= loc && loc < @last
    end

    def contain?(other)
      @first <= other.first && other.last <= @last
    end

    def overlap?(other)
      if @first <= other.first
        return @last > other.first
      else
        return @first < other.last
      end
    end
  end

  class CodeRangeTable
    Entry = Struct.new(:range, :value, :children)

    class Entry
      def inspect
        "[%p, %p, %p]" % [range, value, children]
      end
    end

    def initialize(list = [])
      @list = list # Array[Entry]
    end

    def []=(range, value)
      i_b = @list.bsearch_index {|e| e.range.last > range.first } || @list.size
      i_e = @list.bsearch_index {|e| e.range.first >= range.last } || @list.size
      if i_b < i_e
        # for all i in i_b...i_e, @list[i] overlaps with the range
        if i_e - i_b == 1
          if range.contain?(@list[i_b].range)
            @list[i_b] = Entry[range, value, CodeRangeTable.new(@list[i_b, 1])]
          elsif @list[i_b].range.contain?(range)
            @list[i_b].children[range] = value
          else
            raise
          end
        else
          if range.contain?(@list[i_b].range) && range.contain?(@list[i_e - 1].range)
            @list[i_b...i_e] = [Entry[range, value, CodeRangeTable.new(@list[i_b...i_e])]]
          else
            raise
          end
        end
      else
        @list[i_b, 0] = [Entry[range, value, CodeRangeTable.new]]
      end
    end

    def [](loc)
      e = @list.bsearch {|e| e.range.last > loc }
      if e && e.range.contain_loc?(loc)
        return e.children[loc] || e.value
      end
      return nil
    end
  end
end

if $0 == __FILE__
  include TypeProf
  cr1 = CodeRange.new(CodeLocation.new(1, 0), CodeLocation.new(1, 2))
  cr2 = CodeRange.new(CodeLocation.new(1, 2), CodeLocation.new(1, 4))
  cr3 = CodeRange.new(CodeLocation.new(2, 0), CodeLocation.new(2, 2))
  cr4 = CodeRange.new(CodeLocation.new(2, 3), CodeLocation.new(2, 5))
  cr1and2 = CodeRange.new(CodeLocation.new(1, 0), CodeLocation.new(1, 5))
  cr3and4 = CodeRange.new(CodeLocation.new(2, 0), CodeLocation.new(2, 5))
  [[cr1, "A"], [cr2, "B"], [cr3, "C"], [cr4, "D"], [cr1and2, "AB"], [cr3and4, "CD"]].permutation do |ary|
    tbl = CodeRangeTable.new
    ary.each do |cr, v|
      tbl[cr] = v
    end
    values = []
    [1, 2].each do |lineno|
      (0..5).each do |column|
        values << tbl[CodeLocation.new(lineno, column)]
      end
    end
    raise if values != ["A", "A", "B", "B", "AB", nil, "C", "C", "CD", "D", "D", nil]
  end

  source = <<~EOS
  AB
  CDE
  F
  EOS
  a_loc = CodeLocation.new(1, 0)
  b_loc = a_loc.advance_cursor(1, source)
  raise unless b_loc.inspect == "(1,1)"
  c_loc = a_loc.advance_cursor(3, source)
  raise unless c_loc.inspect == "(2,0)"
  f_loc = c_loc.advance_cursor(4, source)
  raise unless f_loc.inspect == "(3,0)"
end
