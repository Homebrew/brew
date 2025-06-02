# frozen-string-literal: true

module DidYouMean
  # The +DidYouMean::Formatter+ is the basic, default formatter for the
  # gem. The formatter responds to the +message_for+ method and it returns a
  # human readable string.
  class Formatter

    # Returns a human readable string that contains +corrections+. This
    # formatter is designed to be less verbose to not take too much screen
    # space while being helpful enough to the user.
    #
    # @example
    #
    #   formatter = DidYouMean::Formatter.new
    #
    #   # displays suggestions in two lines with the leading empty line
    #   puts formatter.message_for(["methods", "method"])
    #
    #   Did you mean?  methods
    #                   method
    #   # => nil
    #
    #   # displays an empty line
    #   puts formatter.message_for([])
    #
    #   # => nil
    #
    def self.message_for(corrections)
      corrections.empty? ? "" : "\nDid you mean?  #{corrections.join("\n               ")}"
    end

    def message_for(corrections)
      warn "The instance method #message_for has been deprecated. Please use the class method " \
           "DidYouMean::Formatter.message_for(...) instead."

      self.class.message_for(corrections)
    end
  end

  PlainFormatter = Formatter

  deprecate_constant :PlainFormatter
end
