require_relative "formatter"

module ErrorHighlight
  module CoreExt
    private def generate_snippet
      spot = ErrorHighlight.spot(self)
      return "" unless spot
      return ErrorHighlight.formatter.message_for(spot)
    end

    if Exception.method_defined?(:detailed_message)
      def detailed_message(highlight: false, error_highlight: true, **)
        return super unless error_highlight
        snippet = generate_snippet
        if highlight
          snippet = snippet.gsub(/.+/) { "\e[1m" + $& + "\e[m" }
        end
        super + snippet
      end
    else
      # This is a marker to let `DidYouMean::Correctable#original_message` skip
      # the following method definition of `to_s`.
      # See https://github.com/ruby/did_you_mean/pull/152
      SKIP_TO_S_FOR_SUPER_LOOKUP = true
      private_constant :SKIP_TO_S_FOR_SUPER_LOOKUP

      def to_s
        msg = super
        snippet = generate_snippet
        if snippet != "" && !msg.include?(snippet)
          msg + snippet
        else
          msg
        end
      end
    end
  end

  NameError.prepend(CoreExt)

  if Exception.method_defined?(:detailed_message)
    # ErrorHighlight is enabled for TypeError and ArgumentError only when Exception#detailed_message is available.
    # This is because changing ArgumentError#message is highly incompatible.
    TypeError.prepend(CoreExt)
    ArgumentError.prepend(CoreExt)
  end
end
