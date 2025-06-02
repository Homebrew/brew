# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # This class represents a
    # {YAML sequence}[http://yaml.org/spec/1.1/#sequence/syntax].
    #
    # A YAML sequence is basically a list, and looks like this:
    #
    #   %YAML 1.1
    #   ---
    #   - I am
    #   - a Sequence
    #
    # A YAML sequence may have an anchor like this:
    #
    #   %YAML 1.1
    #   ---
    #   &A [
    #     "This sequence",
    #     "has an anchor"
    #   ]
    #
    # A YAML sequence may also have a tag like this:
    #
    #   %YAML 1.1
    #   ---
    #   !!seq [
    #     "This sequence",
    #     "has a tag"
    #   ]
    #
    # This class represents a sequence in a YAML document.  A
    # Psych::Nodes::Sequence node may have 0 or more children.  Valid children
    # for this node are:
    #
    # * Psych::Nodes::Sequence
    # * Psych::Nodes::Mapping
    # * Psych::Nodes::Scalar
    # * Psych::Nodes::Alias
    class Sequence < Psych::Nodes::Node
      # Any Styles, emitter chooses
      ANY   = 0

      # Block style sequence
      BLOCK = 1

      # Flow style sequence
      FLOW  = 2

      # The anchor for this sequence (if any)
      attr_accessor :anchor

      # The tag name for this sequence (if any)
      attr_accessor :tag

      # Is this sequence started implicitly?
      attr_accessor :implicit

      # The sequence style used
      attr_accessor :style

      ###
      # Create a new object representing a YAML sequence.
      #
      # +anchor+ is the anchor associated with the sequence or nil.
      # +tag+ is the tag associated with the sequence or nil.
      # +implicit+ a boolean indicating whether or not the sequence was
      # implicitly started.
      # +style+ is an integer indicating the list style.
      #
      # See Psych::Handler#start_sequence
      def initialize anchor = nil, tag = nil, implicit = true, style = BLOCK
        super()
        @anchor   = anchor
        @tag      = tag
        @implicit = implicit
        @style    = style
      end

      def sequence?; true; end
    end
  end
end
