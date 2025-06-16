# typed: strict
# frozen_string_literal: true

module Homebrew
  class FormulaNameCaskTokenAuditor
    sig { returns(String) }
    attr_reader :token

    sig { params(token: String).void }
    def initialize(token)
      @token = token
    end

    sig { returns(T::Array[String]) }
    def errors
      errors = []

      errors << "uppercase letters" if token.match?(/[A-Z]/)
      errors << "whitespace" if token.match?(/\s/)
      errors << "non-ASCII characters" unless token.ascii_only?
      errors << "double hyphens" if token.include?("--")

      errors << "a leading @" if token.start_with?("@")
      errors << "a trailing @" if token.end_with?("@")
      errors << "a leading hyphen" if token.start_with?("-")
      errors << "a trailing hyphen" if token.end_with?("-")

      errors << "multiple @ symbols" if token.count("@") > 1

      errors << "a hyphen followed by an @" if token.include? "-@"
      errors << "an @ followed by a hyphen" if token.include? "@-"

      errors
    end
  end
end
