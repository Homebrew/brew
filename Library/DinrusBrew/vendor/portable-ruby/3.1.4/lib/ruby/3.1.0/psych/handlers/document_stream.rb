# frozen_string_literal: true
require_relative '../tree_builder'

module Psych
  module Handlers
    class DocumentStream < Psych::TreeBuilder # :nodoc:
      def initialize &block
        super
        @block = block
      end

      def start_document version, tag_directives, implicit
        n = Nodes::Document.new version, tag_directives, implicit
        push n
      end

      def end_document implicit_end = !streaming?
        @last.implicit_end = implicit_end
        @block.call pop
      end
    end
  end
end
