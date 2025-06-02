# frozen_string_literal: false
#
#   change-ws.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "nop"
require_relative "../ext/workspaces"

# :stopdoc:
module IRB
  module ExtendCommand
    class Workspaces < Nop
      def execute(*obj)
        irb_context.workspaces.collect{|ws| ws.main}
      end
    end

    class PushWorkspace < Workspaces
      def execute(*obj)
        irb_context.push_workspace(*obj)
        super
      end
    end

    class PopWorkspace < Workspaces
      def execute(*obj)
        irb_context.pop_workspace(*obj)
        super
      end
    end
  end
end
# :startdoc:
