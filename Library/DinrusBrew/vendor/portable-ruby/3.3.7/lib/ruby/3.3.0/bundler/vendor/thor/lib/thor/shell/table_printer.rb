require_relative "column_printer"
require_relative "terminal"

class Bundler::Thor
  module Shell
    class TablePrinter < ColumnPrinter
      BORDER_SEPARATOR = :separator

      def initialize(stdout, options = {})
        super
        @formats = []
        @maximas = []
        @colwidth = options[:colwidth]
        @truncate = options[:truncate] == true ? Terminal.terminal_width : options[:truncate]
        @padding = 1
      end

      def print(array)
        return if array.empty?

        prepare(array)

        print_border_separator if options[:borders]

        array.each do |row|
          if options[:borders] && row == BORDER_SEPARATOR
            print_border_separator
            next
          end

          sentence = "".dup

          row.each_with_index do |column, index|
            sentence << format_cell(column, row.size, index)
          end

          sentence = truncate(sentence)
          sentence << "|" if options[:borders]
          stdout.puts indentation + sentence

        end
        print_border_separator if options[:borders]
      end

    private

      def prepare(array)
        array = array.reject{|row| row == BORDER_SEPARATOR }

        @formats << "%-#{@colwidth + 2}s".dup if @colwidth
        start = @colwidth ? 1 : 0

        colcount = array.max { |a, b| a.size <=> b.size }.size

        start.upto(colcount - 1) do |index|
          maxima = array.map { |row| row[index] ? row[index].to_s.size : 0 }.max

          @maximas << maxima
          @formats << if options[:borders]
             "%-#{maxima}s".dup
          elsif index == colcount - 1
            # Don't output 2 trailing spaces when printing the last column
            "%-s".dup
          else
            "%-#{maxima + 2}s".dup
          end
        end

        @formats << "%s"
      end

      def format_cell(column, row_size, index)
        maxima = @maximas[index]

        f = if column.is_a?(Numeric)
          if options[:borders]
            # With borders we handle padding separately
            "%#{maxima}s"
          elsif index == row_size - 1
            # Don't output 2 trailing spaces when printing the last column
            "%#{maxima}s"
          else
            "%#{maxima}s  "
          end
        else
          @formats[index]
        end

        cell = "".dup
        cell << "|" + " " * @padding if options[:borders]
        cell << f % column.to_s
        cell << " " * @padding if options[:borders]
        cell
      end

      def print_border_separator
        separator = @maximas.map do |maxima|
          "+" + "-" * (maxima + 2 * @padding)
        end
        stdout.puts indentation + separator.join + "+"
      end

      def truncate(string)
        return string unless @truncate
        as_unicode do
          chars = string.chars.to_a
          if chars.length <= @truncate
            chars.join
          else
            chars[0, @truncate - 3 - @indent].join + "..."
          end
        end
      end

      def indentation
        " " * @indent
      end

      if "".respond_to?(:encode)
        def as_unicode
          yield
        end
      else
        def as_unicode
          old = $KCODE # rubocop:disable Style/GlobalVars
          $KCODE = "U" # rubocop:disable Style/GlobalVars
          yield
        ensure
          $KCODE = old # rubocop:disable Style/GlobalVars
        end
      end
    end
  end
end
