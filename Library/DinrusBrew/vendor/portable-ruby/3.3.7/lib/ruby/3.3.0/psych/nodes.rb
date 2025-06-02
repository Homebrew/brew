# frozen_string_literal: true
require_relative 'nodes/node'
require_relative 'nodes/stream'
require_relative 'nodes/document'
require_relative 'nodes/sequence'
require_relative 'nodes/scalar'
require_relative 'nodes/mapping'
require_relative 'nodes/alias'

module Psych
  ###
  # = Overview
  #
  # When using Psych.load to deserialize a YAML document, the document is
  # translated to an intermediary AST.  That intermediary AST is then
  # translated in to a Ruby object graph.
  #
  # In the opposite direction, when using Psych.dump, the Ruby object graph is
  # translated to an intermediary AST which is then converted to a YAML
  # document.
  #
  # Psych::Nodes contains all of the classes that make up the nodes of a YAML
  # AST.  You can manually build an AST and use one of the visitors (see
  # Psych::Visitors) to convert that AST to either a YAML document or to a
  # Ruby object graph.
  #
  # Here is an example of building an AST that represents a list with one
  # scalar:
  #
  #   # Create our nodes
  #   stream = Psych::Nodes::Stream.new
  #   doc    = Psych::Nodes::Document.new
  #   seq    = Psych::Nodes::Sequence.new
  #   scalar = Psych::Nodes::Scalar.new('foo')
  #
  #   # Build up our tree
  #   stream.children << doc
  #   doc.children    << seq
  #   seq.children    << scalar
  #
  # The stream is the root of the tree.  We can then convert the tree to YAML:
  #
  #   stream.to_yaml => "---\n- foo\n"
  #
  # Or convert it to Ruby:
  #
  #   stream.to_ruby => [["foo"]]
  #
  # == YAML AST Requirements
  #
  # A valid YAML AST *must* have one Psych::Nodes::Stream at the root.  A
  # Psych::Nodes::Stream node must have 1 or more Psych::Nodes::Document nodes
  # as children.
  #
  # Psych::Nodes::Document nodes must have one and *only* one child.  That child
  # may be one of:
  #
  # * Psych::Nodes::Sequence
  # * Psych::Nodes::Mapping
  # * Psych::Nodes::Scalar
  #
  # Psych::Nodes::Sequence and Psych::Nodes::Mapping nodes may have many
  # children, but Psych::Nodes::Mapping nodes should have an even number of
  # children.
  #
  # All of these are valid children for Psych::Nodes::Sequence and
  # Psych::Nodes::Mapping nodes:
  #
  # * Psych::Nodes::Sequence
  # * Psych::Nodes::Mapping
  # * Psych::Nodes::Scalar
  # * Psych::Nodes::Alias
  #
  # Psych::Nodes::Scalar and Psych::Nodes::Alias are both terminal nodes and
  # should not have any children.
  module Nodes
  end
end
