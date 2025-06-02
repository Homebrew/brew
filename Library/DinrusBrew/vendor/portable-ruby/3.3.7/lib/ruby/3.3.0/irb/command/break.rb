# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module Command
    class Break < DebugCommand
      def execute(arg)
        execute_debug_command(pre_cmds: "break #{arg}")
      end
    end
  end

  # :startdoc:
end
