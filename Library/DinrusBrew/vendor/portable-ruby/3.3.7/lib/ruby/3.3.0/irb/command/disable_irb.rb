# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class DisableIrb < Base
      category "IRB"
      description "Disable binding.irb."

      def execute(*)
        ::Binding.define_method(:irb) {}
        IRB.irb_exit
      end
    end
  end

  # :startdoc:
end
