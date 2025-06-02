# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class Whereami < Base
      category "Context"
      description "Show the source code around binding.irb again."

      def execute(_arg)
        code = irb_context.workspace.code_around_binding
        if code
          puts code
        else
          puts "The current context doesn't have code."
        end
      end
    end
  end

  # :startdoc:
end
