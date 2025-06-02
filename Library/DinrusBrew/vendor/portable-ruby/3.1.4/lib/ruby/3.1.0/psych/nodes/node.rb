# frozen_string_literal: true
require 'stringio'
require_relative '../class_loader'
require_relative '../scalar_scanner'

module Psych
  module Nodes
    ###
    # The base class for any Node in a YAML parse tree.  This class should
    # never be instantiated.
    class Node
      include Enumerable

      # The children of this node
      attr_reader :children

      # An associated tag
      attr_reader :tag

      # The line number where this node start
      attr_accessor :start_line

      # The column number where this node start
      attr_accessor :start_column

      # The line number where this node ends
      attr_accessor :end_line

      # The column number where this node ends
      attr_accessor :end_column

      # Create a new Psych::Nodes::Node
      def initialize
        @children = []
      end

      ###
      # Iterate over each node in the tree. Yields each node to +block+ depth
      # first.
      def each &block
        return enum_for :each unless block_given?
        Visitors::DepthFirst.new(block).accept self
      end

      ###
      # Convert this node to Ruby.
      #
      # See also Psych::Visitors::ToRuby
      def to_ruby(symbolize_names: false, freeze: false, strict_integer: false)
        Visitors::ToRuby.create(symbolize_names: symbolize_names, freeze: freeze, strict_integer: strict_integer).accept(self)
      end
      alias :transform :to_ruby

      ###
      # Convert this node to YAML.
      #
      # See also Psych::Visitors::Emitter
      def yaml io = nil, options = {}
        real_io = io || StringIO.new(''.encode('utf-8'))

        Visitors::Emitter.new(real_io, options).accept self
        return real_io.string unless io
        io
      end
      alias :to_yaml :yaml

      def alias?;    false; end
      def document?; false; end
      def mapping?;  false; end
      def scalar?;   false; end
      def sequence?; false; end
      def stream?;   false; end
    end
  end
end
