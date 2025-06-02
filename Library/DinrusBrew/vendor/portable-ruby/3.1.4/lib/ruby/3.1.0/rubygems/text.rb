# frozen_string_literal: true

##
# A collection of text-wrangling methods

module Gem::Text

  ##
  # Remove any non-printable characters and make the text suitable for
  # printing.
  def clean_text(text)
    text.gsub(/[\000-\b\v-\f\016-\037\177]/, ".".freeze)
  end

  def truncate_text(text, description, max_length = 100_000)
    raise ArgumentError, "max_length must be positive" unless max_length > 0
    return text if text.size <= max_length
    "Truncating #{description} to #{max_length.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse} characters:\n" + text[0, max_length]
  end

  ##
  # Wraps +text+ to +wrap+ characters and optionally indents by +indent+
  # characters

  def format_text(text, wrap, indent=0)
    result = []
    work = clean_text(text)

    while work.length > wrap do
      if work =~ /^(.{0,#{wrap}})[ \n]/
        result << $1.rstrip
        work.slice!(0, $&.length)
      else
        result << work.slice!(0, wrap)
      end
    end

    result << work if work.length.nonzero?
    result.join("\n").gsub(/^/, " " * indent)
  end

  def min3(a, b, c) # :nodoc:
    if a < b && a < c
      a
    elsif b < c
      b
    else
      c
    end
  end

  # Returns a value representing the "cost" of transforming str1 into str2
  # Vendored version of DidYouMean::Levenshtein.distance from the ruby/did_you_mean gem @ 1.4.0
  # https://git.io/JJgZI
  def levenshtein_distance(str1, str2)
    n = str1.length
    m = str2.length
    return m if n.zero?
    return n if m.zero?

    d = (0..m).to_a
    x = nil

    # to avoid duplicating an enumerable object, create it outside of the loop
    str2_codepoints = str2.codepoints

    str1.each_codepoint.with_index(1) do |char1, i|
      j = 0
      while j < m
        cost = (char1 == str2_codepoints[j]) ? 0 : 1
        x = min3(
          d[j + 1] + 1, # insertion
          i + 1,      # deletion
          d[j] + cost # substitution
        )
        d[j] = i
        i = x

        j += 1
      end
      d[m] = x
    end

    x
  end
end
