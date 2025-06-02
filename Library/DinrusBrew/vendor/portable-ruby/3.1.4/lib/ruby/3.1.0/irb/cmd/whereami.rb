# frozen_string_literal: true

require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Whereami < Nop
      def execute(*)
        code = irb_context.workspace.code_around_binding
        if code
          puts code
        else
          puts "The current context doesn't have code."
        end
      end
    end
  end
end
# :startdoc:
