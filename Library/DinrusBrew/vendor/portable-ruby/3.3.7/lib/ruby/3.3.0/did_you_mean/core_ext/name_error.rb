module DidYouMean
  module Correctable
    if Exception.method_defined?(:detailed_message)
      # just for compatibility
      def original_message
        # we cannot use alias here because
        to_s
      end

      def detailed_message(highlight: true, did_you_mean: true, **)
        msg = super.dup

        return msg unless did_you_mean

        suggestion = DidYouMean.formatter.message_for(corrections)

        if highlight
          suggestion = suggestion.gsub(/.+/) { "\e[1m" + $& + "\e[m" }
        end

        msg << suggestion
        msg
      rescue
        super
      end
    else
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
    end

    def corrections
      @corrections ||= spell_checker.corrections
    end

    def spell_checker
      DidYouMean.spell_checkers[self.class.to_s].new(self)
    end
  end
end
