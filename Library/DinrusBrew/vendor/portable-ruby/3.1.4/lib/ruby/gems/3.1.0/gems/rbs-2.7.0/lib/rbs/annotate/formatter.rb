# frozen_string_literal: true

module RBS
  module Annotate
    class Formatter
      attr_reader :buffer

      def initialize()
        @buffer = +""
        @pending_separator = nil
      end

      def <<(s)
        if s
          if s.is_a?(RDoc::Markup::Document)
            s = self.class.translate(s) or raise
          end

          s = s.rstrip

          unless s.empty?
            if ss = @pending_separator
              buffer << ss
              buffer << "\n"
              @pending_separator = nil
            end

            buffer << s
            buffer << "\n"
          end
        end

        self
      end

      def margin(separator: "")
        unless buffer.empty?
          @pending_separator = separator
        end

        self
      end

      def empty?
        buffer.empty?
      end

      def format(newline_at_end:)
        unless buffer.empty?
          if newline_at_end
            buffer.strip + "\n\n"
          else
            buffer.strip + "\n"
          end
        else
          buffer
        end
      end

      def self.each_part(doc, &block)
        if block
          if doc.file
            yield doc
          else
            doc.each do |d|
              each_part(d, &block)
            end
          end
        else
          enum_for :each_part, doc
        end
      end

      def self.translate(doc)
        if doc.file
          formatter = RDoc::Markup::ToMarkdown.new
          doc.accept(formatter).strip.lines.map(&:rstrip).join("\n")
        end
      end
    end
  end
end
