# frozen_string_literal: true

module SyntaxSuggest
  # Represents a single line of code of a given source file
  #
  # This object contains metadata about the line such as
  # amount of indentation, if it is empty or not, and
  # lexical data, such as if it has an `end` or a keyword
  # in it.
  #
  # Visibility of lines can be toggled off. Marking a line as invisible
  # indicates that it should not be used for syntax checks.
  # It's functionally the same as commenting it out.
  #
  # Example:
  #
  #   line = CodeLine.from_source("def foo\n").first
  #   line.number => 1
  #   line.empty? # => false
  #   line.visible? # => true
  #   line.mark_invisible
  #   line.visible? # => false
  #
  class CodeLine
    TRAILING_SLASH = ("\\" + $/).freeze

    # Returns an array of CodeLine objects
    # from the source string
    def self.from_source(source, lines: nil)
      lines ||= source.lines
      lex_array_for_line = LexAll.new(source: source, source_lines: lines).each_with_object(Hash.new { |h, k| h[k] = [] }) { |lex, hash| hash[lex.line] << lex }
      lines.map.with_index do |line, index|
        CodeLine.new(
          line: line,
          index: index,
          lex: lex_array_for_line[index + 1]
        )
      end
    end

    attr_reader :line, :index, :lex, :line_number, :indent
    def initialize(line:, index:, lex:)
      @lex = lex
      @line = line
      @index = index
      @original = line
      @line_number = @index + 1
      strip_line = line.dup
      strip_line.lstrip!

      @indent = if (@empty = strip_line.empty?)
        line.length - 1 # Newline removed from strip_line is not "whitespace"
      else
        line.length - strip_line.length
      end

      set_kw_end
    end

    # Used for stable sort via indentation level
    #
    # Ruby's sort is not "stable" meaning that when
    # multiple elements have the same value, they are
    # not guaranteed to return in the same order they
    # were put in.
    #
    # So when multiple code lines have the same indentation
    # level, they're sorted by their index value which is unique
    # and consistent.
    #
    # This is mostly needed for consistency of the test suite
    def indent_index
      @indent_index ||= [indent, index]
    end
    alias_method :number, :line_number

    # Returns true if the code line is determined
    # to contain a keyword that matches with an `end`
    #
    # For example: `def`, `do`, `begin`, `ensure`, etc.
    def is_kw?
      @is_kw
    end

    # Returns true if the code line is determined
    # to contain an `end` keyword
    def is_end?
      @is_end
    end

    # Used to hide lines
    #
    # The search alorithm will group lines into blocks
    # then if those blocks are determined to represent
    # valid code they will be hidden
    def mark_invisible
      @line = ""
    end

    # Means the line was marked as "invisible"
    # Confusingly, "empty" lines are visible...they
    # just don't contain any source code other than a newline ("\n").
    def visible?
      !line.empty?
    end

    # Opposite or `visible?` (note: different than `empty?`)
    def hidden?
      !visible?
    end

    # An `empty?` line is one that was originally left
    # empty in the source code, while a "hidden" line
    # is one that we've since marked as "invisible"
    def empty?
      @empty
    end

    # Opposite of `empty?` (note: different than `visible?`)
    def not_empty?
      !empty?
    end

    # Renders the given line
    #
    # Also allows us to represent source code as
    # an array of code lines.
    #
    # When we have an array of code line elements
    # calling `join` on the array will call `to_s`
    # on each element, which essentially converts
    # it back into it's original source string.
    def to_s
      line
    end

    # When the code line is marked invisible
    # we retain the original value of it's line
    # this is useful for debugging and for
    # showing extra context
    #
    # DisplayCodeWithLineNumbers will render
    # all lines given to it, not just visible
    # lines, it uses the original method to
    # obtain them.
    attr_reader :original

    # Comparison operator, needed for equality
    # and sorting
    def <=>(other)
      index <=> other.index
    end

    # [Not stable API]
    #
    # Lines that have a `on_ignored_nl` type token and NOT
    # a `BEG` type seem to be a good proxy for the ability
    # to join multiple lines into one.
    #
    # This predicate method is used to determine when those
    # two criteria have been met.
    #
    # The one known case this doesn't handle is:
    #
    #     Ripper.lex <<~EOM
    #       a &&
    #        b ||
    #        c
    #     EOM
    #
    # For some reason this introduces `on_ignore_newline` but with BEG type
    def ignore_newline_not_beg?
      @ignore_newline_not_beg
    end

    # Determines if the given line has a trailing slash
    #
    #     lines = CodeLine.from_source(<<~EOM)
    #       it "foo" \
    #     EOM
    #     expect(lines.first.trailing_slash?).to eq(true)
    #
    if SyntaxSuggest.use_prism_parser?
      def trailing_slash?
        last = @lex.last
        last&.type == :on_tstring_end
      end
    else
      def trailing_slash?
        last = @lex.last
        return false unless last
        return false unless last.type == :on_sp

        last.token == TRAILING_SLASH
      end
    end

    # Endless method detection
    #
    # From https://github.com/ruby/irb/commit/826ae909c9c93a2ddca6f9cfcd9c94dbf53d44ab
    # Detecting a "oneliner" seems to need a state machine.
    # This can be done by looking mostly at the "state" (last value):
    #
    #   ENDFN -> BEG (token = '=' ) -> END
    #
    private def set_kw_end
      oneliner_count = 0
      in_oneliner_def = nil

      kw_count = 0
      end_count = 0

      @ignore_newline_not_beg = false
      @lex.each do |lex|
        kw_count += 1 if lex.is_kw?
        end_count += 1 if lex.is_end?

        if lex.type == :on_ignored_nl
          @ignore_newline_not_beg = !lex.expr_beg?
        end

        if in_oneliner_def.nil?
          in_oneliner_def = :ENDFN if lex.state.allbits?(Ripper::EXPR_ENDFN)
        elsif lex.state.allbits?(Ripper::EXPR_ENDFN)
          # Continue
        elsif lex.state.allbits?(Ripper::EXPR_BEG)
          in_oneliner_def = :BODY if lex.token == "="
        elsif lex.state.allbits?(Ripper::EXPR_END)
          # We found an endless method, count it
          oneliner_count += 1 if in_oneliner_def == :BODY

          in_oneliner_def = nil
        else
          in_oneliner_def = nil
        end
      end

      kw_count -= oneliner_count

      @is_kw = (kw_count - end_count) > 0
      @is_end = (end_count - kw_count) > 0
    end
  end
end
