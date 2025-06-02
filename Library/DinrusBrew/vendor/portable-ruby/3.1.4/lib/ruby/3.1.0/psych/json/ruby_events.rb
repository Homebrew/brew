# frozen_string_literal: true
module Psych
  module JSON
    module RubyEvents # :nodoc:
      def visit_Time o
        formatted = format_time o
        @emitter.scalar formatted, nil, nil, false, true, Nodes::Scalar::DOUBLE_QUOTED
      end

      def visit_DateTime o
        visit_Time o.to_time
      end

      def visit_String o
        @emitter.scalar o.to_s, nil, nil, false, true, Nodes::Scalar::DOUBLE_QUOTED
      end
      alias :visit_Symbol :visit_String
    end
  end
end
