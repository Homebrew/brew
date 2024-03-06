# typed: strict
# frozen_string_literal: true

module Homebrew
  # A location in source code.
  class SourceLocation
    sig { returns(Integer) }
    attr_reader :line

    sig { returns(T.nilable(Integer)) }
    attr_reader :column

    sig { params(line: Integer, column: T.nilable(Integer)).void }
    def initialize(line, column = T.unsafe(nil))
      @line = line
      @column = column
    end

    sig { returns(String) }
    def to_s
      "#{line}#{column&.to_s&.prepend(":")}"
    end
  end
end
