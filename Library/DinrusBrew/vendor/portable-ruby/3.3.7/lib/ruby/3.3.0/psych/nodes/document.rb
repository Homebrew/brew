# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # This represents a YAML Document.  This node must be a child of
    # Psych::Nodes::Stream.  A Psych::Nodes::Document must have one child,
    # and that child may be one of the following:
    #
    # * Psych::Nodes::Sequence
    # * Psych::Nodes::Mapping
    # * Psych::Nodes::Scalar
    class Document < Psych::Nodes::Node
      # The version of the YAML document
      attr_accessor :version

      # A list of tag directives for this document
      attr_accessor :tag_directives

      # Was this document implicitly created?
      attr_accessor :implicit

      # Is the end of the document implicit?
      attr_accessor :implicit_end

      ###
      # Create a new Psych::Nodes::Document object.
      #
      # +version+ is a list indicating the YAML version.
      # +tags_directives+ is a list of tag directive declarations
      # +implicit+ is a flag indicating whether the document will be implicitly
      # started.
      #
      # == Example:
      # This creates a YAML document object that represents a YAML 1.1 document
      # with one tag directive, and has an implicit start:
      #
      #   Psych::Nodes::Document.new(
      #     [1,1],
      #     [["!", "tag:tenderlovemaking.com,2009:"]],
      #     true
      #   )
      #
      # == See Also
      # See also Psych::Handler#start_document
      def initialize version = [], tag_directives = [], implicit = false
        super()
        @version        = version
        @tag_directives = tag_directives
        @implicit       = implicit
        @implicit_end   = true
      end

      ###
      # Returns the root node.  A Document may only have one root node:
      # http://yaml.org/spec/1.1/#id898031
      def root
        children.first
      end

      def document?; true; end
    end
  end
end
