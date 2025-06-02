# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module Command
    class Step < DebugCommand
      def execute(arg)
        execute_debug_command(do_cmds: "step #{arg}")
      end
    end
  end

  # :startdoc:
end
