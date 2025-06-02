# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # Represents a YAML stream.  This is the root node for any YAML parse
    # tree.  This node must have one or more child nodes.  The only valid
    # child node for a Psych::Nodes::Stream node is Psych::Nodes::Document.
    class Stream < Psych::Nodes::Node

      # Encodings supported by Psych (and libyaml)

      # Any encoding
      ANY     = Psych::Parser::ANY

      # UTF-8 encoding
      UTF8    = Psych::Parser::UTF8

      # UTF-16LE encoding
      UTF16LE = Psych::Parser::UTF16LE

      # UTF-16BE encoding
      UTF16BE = Psych::Parser::UTF16BE

      # The encoding used for this stream
      attr_accessor :encoding

      ###
      # Create a new Psych::Nodes::Stream node with an +encoding+ that
      # defaults to Psych::Nodes::Stream::UTF8.
      #
      # See also Psych::Handler#start_stream
      def initialize encoding = UTF8
        super()
        @encoding = encoding
      end

      def stream?; true; end
    end
  end
end
