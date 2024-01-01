# typed: true
# frozen_string_literal: true

require_relative "../extend/module"
require_relative "../warnings"
Warnings.ignore :parser_syntax do
  require "parser/current"
end

module Homebrew
  # Parlour type signature generator helper class for Homebrew.
  module Parlour
    ROOT_DIR = T.let(Pathname(T.must(__dir__)).parent.realpath.freeze, Pathname).freeze

    sig { returns(T::Array[Parser::AST::Node]) }
    def self.ast_list
      @ast_list ||= begin
        ast_list = []
        parser = Parser::CurrentRuby.new
        prune_dirs = %w[sorbet shims test vendor].freeze

        ROOT_DIR.find do |path|
          Find.prune if path.directory? && prune_dirs.any? { |subdir| path == ROOT_DIR/subdir }

          Find.prune if path.file? && path.extname != ".rb"

          next unless path.file?

          buffer = Parser::Source::Buffer.new(path, source: path.read)

          parser.reset
          ast = parser.parse(buffer)
          ast_list << ast if ast
        end

        ast_list
      end
    end
  end
end

require "parlour"
require_relative "parlour/attr"
