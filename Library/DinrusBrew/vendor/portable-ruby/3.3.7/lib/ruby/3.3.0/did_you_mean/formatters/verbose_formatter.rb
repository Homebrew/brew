# frozen-string-literal: true

warn "`require 'did_you_mean/formatters/verbose_formatter'` is deprecated and falls back to the default formatter. "

require_relative '../formatter'

module DidYouMean
  # For compatibility:
  VerboseFormatter = Formatter
end
