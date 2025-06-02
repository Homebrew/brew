# frozen_string_literal: true

module SyntaxSuggest
  # Ripper.lex is not guaranteed to lex the entire source document
  #
  # This class guarantees the whole document is lex-ed by iteratively
  # lexing the document where ripper stopped.
  #
  # Prism likely doesn't have the same problem. Once ripper support is removed
  # we can likely reduce the complexity here if not remove the whole concept.
  #
  # Example usage:
  #
  #   lex = LexAll.new(source: source)
  #   lex.each do |value|
  #     puts value.line
  #   end
  class LexAll
    include Enumerable

    def initialize(source:, source_lines: nil)
      @lex = self.class.lex(source, 1)
      lineno = @lex.last[0][0] + 1
      source_lines ||= source.lines
      last_lineno = source_lines.length

      until lineno >= last_lineno
        lines = source_lines[lineno..]

        @lex.concat(
          self.class.lex(lines.join, lineno + 1)
        )

        lineno = @lex.last[0].first + 1
      end

      last_lex = nil
      @lex.map! { |elem|
        last_lex = LexValue.new(elem[0].first, elem[1], elem[2], elem[3], last_lex)
      }
    end

    if SyntaxSuggest.use_prism_parser?
      def self.lex(source, line_number)
        Prism.lex_compat(source, line: line_number).value.sort_by { |values| values[0] }
      end
    else
      def self.lex(source, line_number)
        Ripper::Lexer.new(source, "-", line_number).parse.sort_by(&:pos)
      end
    end

    def to_a
      @lex
    end

    def each
      return @lex.each unless block_given?
      @lex.each do |x|
        yield x
      end
    end

    def [](index)
      @lex[index]
    end

    def last
      @lex.last
    end
  end
end

require_relative "lex_value"
