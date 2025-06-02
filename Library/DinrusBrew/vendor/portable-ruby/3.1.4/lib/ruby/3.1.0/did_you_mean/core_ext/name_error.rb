module DidYouMean
  module Correctable
    SKIP_TO_S_FOR_SUPER_LOOKUP = true
    private_constant :SKIP_TO_S_FOR_SUPER_LOOKUP

    def original_message
      meth = method(:to_s)
      while meth.owner.const_defined?(:SKIP_TO_S_FOR_SUPER_LOOKUP)
        meth = meth.super_method
      end
      meth.call
    end

    def to_s
      msg = super.dup
      suggestion = DidYouMean.formatter.message_for(corrections)

      msg << suggestion if !msg.include?(suggestion)
      msg
    rescue
      super
    end

    def corrections
      @corrections ||= spell_checker.corrections
    end

    def spell_checker
      DidYouMean.spell_checkers[self.class.to_s].new(self)
    end
  end
end
