#) frozen_string_literal: true
require_relative "parser"

class Gem::RequestSet::Lockfile::Tokenizer
  Token = Struct.new :type, :value, :column, :line
  EOF   = Token.new :EOF

  def self.from_file(file)
    new File.read(file), file
  end

  def initialize(input, filename = nil, line = 0, pos = 0)
    @line     = line
    @line_pos = pos
    @tokens   = []
    @filename = filename
    tokenize input
  end

  def make_parser(set, platforms)
    Gem::RequestSet::Lockfile::Parser.new self, set, platforms, @filename
  end

  def to_a
    @tokens.map {|token| [token.type, token.value, token.column, token.line] }
  end

  def skip(type)
    @tokens.shift while !@tokens.empty? && peek.type == type
  end

  ##
  # Calculates the column (by byte) and the line of the current token based on
  # +byte_offset+.

  def token_pos(byte_offset) # :nodoc:
    [byte_offset - @line_pos, @line]
  end

  def empty?
    @tokens.empty?
  end

  def unshift(token)
    @tokens.unshift token
  end

  def next_token
    @tokens.shift
  end
  alias :shift :next_token

  def peek
    @tokens.first || EOF
  end

  private

  def tokenize(input)
    require "strscan"
    s = StringScanner.new input

    until s.eos? do
      pos = s.pos

      pos = s.pos if leading_whitespace = s.scan(/ +/)

      if s.scan(/[<|=>]{7}/)
        message = "your #{@filename} contains merge conflict markers"
        column, line = token_pos pos

        raise Gem::RequestSet::Lockfile::ParseError.new message, column, line, @filename
      end

      @tokens <<
        case
        when s.scan(/\r?\n/) then
          token = Token.new(:newline, nil, *token_pos(pos))
          @line_pos = s.pos
          @line += 1
          token
        when s.scan(/[A-Z]+/) then
          if leading_whitespace
            text = s.matched
            text += s.scan(/[^\s)]*/).to_s # in case of no match
            Token.new(:text, text, *token_pos(pos))
          else
            Token.new(:section, s.matched, *token_pos(pos))
          end
        when s.scan(/([a-z]+):\s/) then
          s.pos -= 1 # rewind for possible newline
          Token.new(:entry, s[1], *token_pos(pos))
        when s.scan(/\(/) then
          Token.new(:l_paren, nil, *token_pos(pos))
        when s.scan(/\)/) then
          Token.new(:r_paren, nil, *token_pos(pos))
        when s.scan(/<=|>=|=|~>|<|>|!=/) then
          Token.new(:requirement, s.matched, *token_pos(pos))
        when s.scan(/,/) then
          Token.new(:comma, nil, *token_pos(pos))
        when s.scan(/!/) then
          Token.new(:bang, nil, *token_pos(pos))
        when s.scan(/[^\s),!]*/) then
          Token.new(:text, s.matched, *token_pos(pos))
        else
          raise "BUG: can't create token for: #{s.string[s.pos..-1].inspect}"
        end
    end

    @tokens
  end
end
