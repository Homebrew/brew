# frozen_string_literal: true
#
#   irb/lc/error.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  class UnrecognizedSwitch < StandardError
    def initialize(val)
      super("Unrecognized switch: #{val}")
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

  # :startdoc:
end
