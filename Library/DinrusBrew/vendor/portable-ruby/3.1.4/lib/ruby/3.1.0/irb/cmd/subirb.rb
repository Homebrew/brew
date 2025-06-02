# frozen_string_literal: false
#   multi.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "nop"
require_relative "../ext/multi-irb"

# :stopdoc:
module IRB
  module ExtendCommand
    class IrbCommand < Nop
      def execute(*obj)
        IRB.irb(nil, *obj)
      end
    end

    class Jobs < Nop
      def execute
        IRB.JobManager
      end
    end

    class Foreground < Nop
      def execute(key)
        IRB.JobManager.switch(key)
      end
    end

    class Kill < Nop
      def execute(*keys)
        IRB.JobManager.kill(*keys)
      end
    end
  end
end
# :startdoc:
