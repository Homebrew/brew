# typed: strict
# frozen_string_literal: true

require "kramdown/parser/kramdown"

module Homebrew
  module Manpages
    module Parser
      # Kramdown parser with compatibility for ronn variable syntax.
      class Ronn < ::Kramdown::Parser::Kramdown
        sig { params(source: String, options: T::Hash[Symbol, T.untyped]).void }
        def initialize(source, options)
          super
          @block_parsers = T.let(@block_parsers, T::Array[Symbol])
          @span_parsers = T.let(@span_parsers, T::Array[Symbol])
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
        sig { returns(T.nilable(Integer)) }
        def parse_variable
          @src = T.let(@src, T.nilable(Kramdown::Utils::StringScanner))
          raise "Ronn src is nil" if @src.nil?

          start_line_number = @src.current_line_number
          @src.scan(VARIABLE_REGEX)
          variable = @src[1]
          @tree = T.let(@tree, T.nilable(Kramdown::Element))
          raise "Ronn tree is nil" if @tree.nil?

          if variable == "br"
            @src.skip(/\n/)
            @tree.children << Element.new(:br, nil, nil, location: start_line_number)
          else
            @tree.children << Element.new(:variable, variable, nil, location: start_line_number)
          end
          start_line_number
        end
        define_parser(:variable, VARIABLE_REGEX, "<")
      end
    end
  end
end
