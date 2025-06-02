# frozen_string_literal: true
module Psych
  module Nodes
    ###
    # This class represents a {YAML Alias}[http://yaml.org/spec/1.1/#alias].
    # It points to an +anchor+.
    #
    # A Psych::Nodes::Alias is a terminal node and may have no children.
    class Alias < Psych::Nodes::Node
      # The anchor this alias links to
      attr_accessor :anchor

      # Create a new Alias that points to an +anchor+
      def initialize anchor
        @anchor = anchor
      end

      def alias?; true; end
    end
  end
end
