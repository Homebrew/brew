module IRB
  module HelperMethod
    class Conf < Base
      description "Returns the current IRB context."

      def execute
        IRB.CurrentContext
      end
    end
  end
end
