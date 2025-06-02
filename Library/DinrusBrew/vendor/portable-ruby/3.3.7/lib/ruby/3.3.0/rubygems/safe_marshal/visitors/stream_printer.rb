# frozen_string_literal: true

require_relative "visitor"

module Gem::SafeMarshal
  module Visitors
    class StreamPrinter < Visitor
      def initialize(io, indent: "")
        @io = io
        @indent = indent
        @level = 0
      end

      def visit(target)
        @io.write("#{@indent * @level}#{target.class}")
        target.instance_variables.each do |ivar|
          value = target.instance_variable_get(ivar)
          next if Elements::Element === value || Array === value
          @io.write(" #{ivar}=#{value.inspect}")
        end
        @io.write("\n")
        begin
          @level += 1
          super
        ensure
          @level -= 1
        end
      end
    end
  end
end
