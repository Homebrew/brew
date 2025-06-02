# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class ForceExit < Base
      category "IRB"
      description "Exit the current process."

      def execute(_arg)
        throw :IRB_EXIT, true
      end
    end
  end

  # :startdoc:
end
