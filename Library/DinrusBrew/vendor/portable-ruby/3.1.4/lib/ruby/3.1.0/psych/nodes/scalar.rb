# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # This class represents a {YAML Scalar}[http://yaml.org/spec/1.1/#id858081].
    #
    # This node type is a terminal node and should not have any children.
    class Scalar < Psych::Nodes::Node
      # Any style scalar, the emitter chooses
      ANY           = 0

      # Plain scalar style
      PLAIN         = 1

      # Single quoted style
      SINGLE_QUOTED = 2

      # Double quoted style
      DOUBLE_QUOTED = 3

      # Literal style
      LITERAL       = 4

      # Folded style
      FOLDED        = 5

      # The scalar value
      attr_accessor :value

      # The anchor value (if there is one)
      attr_accessor :anchor

      # The tag value (if there is one)
      attr_accessor :tag

      # Is this a plain scalar?
      attr_accessor :plain

      # Is this scalar quoted?
      attr_accessor :quoted

      # The style of this scalar
      attr_accessor :style

      ###
      # Create a new Psych::Nodes::Scalar object.
      #
      # +value+ is the string value of the scalar
      # +anchor+ is an associated anchor or nil
      # +tag+ is an associated tag or nil
      # +plain+ is a boolean value
      # +quoted+ is a boolean value
      # +style+ is an integer indicating the string style
      #
      # == See Also
      #
      # See also Psych::Handler#scalar
      def initialize value, anchor = nil, tag = nil, plain = true, quoted = false, style = ANY
        @value  = value
        @anchor = anchor
        @tag    = tag
        @plain  = plain
        @quoted = quoted
        @style  = style
      end

      def scalar?; true; end
    end
  end
end
