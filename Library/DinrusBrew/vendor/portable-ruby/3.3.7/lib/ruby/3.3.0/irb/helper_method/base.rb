require "singleton"

module IRB
  module HelperMethod
    class Base
      include Singleton

      class << self
        def description(description = nil)
          @description = description if description
          @description
        end
      end
    end
  end
end
