# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "kramdown/parser/kramdown"

module Homebrew
  module Manpages
    module Parser
      # Kramdown parser with compatiblity for ronn variable syntax.
      class Ronn < ::Kramdown::Parser::Kramdown
        def initialize(*)
          super
          # Disable HTML parsing and replace it with variable parsing.
          # Also disable table parsing too because it depends on HTML parsing
          # and existing command descriptions may get misinterpreted as tables.
          # Typographic symbols is disabled as it detects `--` as en-dash.
          @block_parsers.delete(:block_html)
          @block_parsers.delete(:table)
          @span_parsers.delete(:span_html)
          @span_parsers.delete(:typographic_syms)
          @span_parsers << :variable
        end

        # HTML-like tags denote variables instead, except <br>.
        VARIABLE_REGEX = /<([\w\-|]+)>/
        def parse_variable
          start_line_number = @src.current_line_number
          @src.scan(VARIABLE_REGEX)
          variable = @src[1]
          if variable == "br"
            @src.skip(/\n/)
            @tree.children << Element.new(:br, nil, nil, location: start_line_number)
          else
            @tree.children << Element.new(:variable, variable, nil, location: start_line_number)
          end
        end
        define_parser(:variable, VARIABLE_REGEX, "<")
      end
    end
  end
end
