# frozen_string_literal: true

module RBS
  class Parser
    def self.parse_type(source, line: 1, column: 0, variables: [])
      _parse_type(buffer(source), line, column, variables)
    end

    def self.parse_method_type(source, line: 1, column: 0, variables: [])
      _parse_method_type(buffer(source), line, column, variables)
    end

    def self.parse_signature(source, line: 1, column: 0)
      _parse_signature(buffer(source), line, column)
    end

    def self.buffer(source)
      case source
      when String
        Buffer.new(content: source, name: "a.rbs")
      when Buffer
        source
      end
    end

    autoload :SyntaxError, "rbs/parser_compat/syntax_error"
    autoload :SemanticsError, "rbs/parser_compat/semantics_error"
    autoload :LexerError, "rbs/parser_compat/lexer_error"
    autoload :LocatedValue, "rbs/parser_compat/located_value"

    KEYWORDS = %w(
      bool
      bot
      class
      instance
      interface
      nil
      self
      singleton
      top
      void
      type
      unchecked
      in
      out
      end
      def
      include
      extend
      prepend
      alias
      module
      attr_reader
      attr_writer
      attr_accessor
      public
      private
      untyped
      true
      false
      ).each_with_object({}) do |keyword, hash|
        hash[keyword] = nil
      end
  end
end
