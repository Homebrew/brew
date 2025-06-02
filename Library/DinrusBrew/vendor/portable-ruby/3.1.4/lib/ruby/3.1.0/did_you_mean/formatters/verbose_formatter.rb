warn "`require 'did_you_mean/formatters/verbose_formatter'` is deprecated and falls back to the default formatter. "

require_relative '../formatter'

# frozen-string-literal: true
module DidYouMean
  # For compatibility:
  VerboseFormatter = Formatter
end
