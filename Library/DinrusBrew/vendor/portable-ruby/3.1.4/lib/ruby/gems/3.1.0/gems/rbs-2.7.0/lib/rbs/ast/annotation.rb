# frozen_string_literal: true

module RBS
  module AST
    class Annotation
      attr_reader :string
      attr_reader :location

      def initialize(string:, location:)
        @string = string
        @location = location
      end

      def ==(other)
        other.is_a?(Annotation) && other.string == string
      end

      alias eql? ==

      def hash
        self.class.hash ^ string.hash
      end

      def to_json(state = _ = nil)
        { string: string, location: location }.to_json(state)
      end
    end
  end
end
