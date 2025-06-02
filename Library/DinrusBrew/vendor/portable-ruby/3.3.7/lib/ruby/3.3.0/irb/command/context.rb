# frozen_string_literal: true

module IRB
  module Command
    class Context < Base
      category "IRB"
      description "Displays current configuration."

      def execute(_arg)
        # This command just displays the configuration.
        # Modifying the configuration is achieved by sending a message to IRB.conf.
        Pager.page_content(IRB.CurrentContext.inspect)
      end
    end
  end
end
