# frozen_string_literal: true
module Psych
  module Visitors
    class DepthFirst < Psych::Visitors::Visitor
      def initialize block
        @block = block
      end

      private

      def nary o
        o.children.each { |x| visit x }
        @block.call o
      end
      alias :visit_Psych_Nodes_Stream   :nary
      alias :visit_Psych_Nodes_Document :nary
      alias :visit_Psych_Nodes_Sequence :nary
      alias :visit_Psych_Nodes_Mapping  :nary

      def terminal o
        @block.call o
      end
      alias :visit_Psych_Nodes_Scalar :terminal
      alias :visit_Psych_Nodes_Alias  :terminal
    end
  end
end
