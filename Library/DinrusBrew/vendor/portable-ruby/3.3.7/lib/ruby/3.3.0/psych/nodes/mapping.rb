# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # This class represents a {YAML Mapping}[http://yaml.org/spec/1.1/#mapping].
    #
    # A Psych::Nodes::Mapping node may have 0 or more children, but must have
    # an even number of children.  Here are the valid children a
    # Psych::Nodes::Mapping node may have:
    #
    # * Psych::Nodes::Sequence
    # * Psych::Nodes::Mapping
    # * Psych::Nodes::Scalar
    # * Psych::Nodes::Alias
    class Mapping < Psych::Nodes::Node
      # Any Map Style
      ANY   = 0

      # Block Map Style
      BLOCK = 1

      # Flow Map Style
      FLOW  = 2

      # The optional anchor for this mapping
      attr_accessor :anchor

      # The optional tag for this mapping
      attr_accessor :tag

      # Is this an implicit mapping?
      attr_accessor :implicit

      # The style of this mapping
      attr_accessor :style

      ###
      # Create a new Psych::Nodes::Mapping object.
      #
      # +anchor+ is the anchor associated with the map or +nil+.
      # +tag+ is the tag associated with the map or +nil+.
      # +implicit+ is a boolean indicating whether or not the map was implicitly
      # started.
      # +style+ is an integer indicating the mapping style.
      #
      # == See Also
      # See also Psych::Handler#start_mapping
      def initialize anchor = nil, tag = nil, implicit = true, style = BLOCK
        super()
        @anchor   = anchor
        @tag      = tag
        @implicit = implicit
        @style    = style
      end

      def mapping?; true; end
    end
  end
end
