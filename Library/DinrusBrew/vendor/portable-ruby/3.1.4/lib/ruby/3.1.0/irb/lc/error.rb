# frozen_string_literal: false
#
#   irb/lc/error.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

# :stopdoc:
module IRB
  class UnrecognizedSwitch < StandardError
    def initialize(val)
      super("Unrecognized switch: #{val}")
    end
  end
  class NotImplementedError < StandardError
    def initialize(val)
      super("Need to define `#{val}'")
    end
  end
  class CantReturnToNormalMode < StandardError
    def initialize
      super("Can't return to normal mode.")
    end
  end
  class IllegalParameter < StandardError
    def initialize(val)
      super("Invalid parameter(#{val}).")
    end
  end
  class IrbAlreadyDead < StandardError
    def initialize
      super("Irb is already dead.")
    end
  end
  class IrbSwitchedToCurrentThread < StandardError
    def initialize
      super("Switched to current thread.")
    end
  end
  class NoSuchJob < StandardError
    def initialize(val)
      super("No such job(#{val}).")
    end
  end
  class CantShiftToMultiIrbMode < StandardError
    def initialize
      super("Can't shift to multi irb mode.")
    end
  end
  class CantChangeBinding < StandardError
    def initialize(val)
      super("Can't change binding to (#{val}).")
    end
  end
  class UndefinedPromptMode < StandardError
    def initialize(val)
      super("Undefined prompt mode(#{val}).")
    end
  end
  class IllegalRCGenerator < StandardError
    def initialize
      super("Define illegal RC_NAME_GENERATOR.")
    end
  end
end
# :startdoc:
