# frozen-string-literal: true

require_relative "levenshtein"
require_relative "jaro_winkler"

module DidYouMean
  class SpellChecker
    def initialize(dictionary:)
      @dictionary = dictionary
    end

    def correct(input)
      normalized_input = normalize(input)
      threshold = normalized_input.length > 3 ? 0.834 : 0.77

      words = @dictionary.select { |word| JaroWinkler.distance(normalize(word), normalized_input) >= threshold }
      words.reject! { |word| input.to_s == word.to_s }
      words.sort_by! { |word| JaroWinkler.distance(word.to_s, normalized_input) }
      words.reverse!

      # Correct mistypes
      threshold   = (normalized_input.length * 0.25).ceil
      corrections = words.select { |c| Levenshtein.distance(normalize(c), normalized_input) <= threshold }

      # Correct misspells
      if corrections.empty?
        corrections = words.select do |word|
          word   = normalize(word)
          length = normalized_input.length < word.length ? normalized_input.length : word.length

          Levenshtein.distance(word, normalized_input) < length
        end.first(1)
      end

      corrections
    end

    private

    def normalize(str_or_symbol) #:nodoc:
      str = str_or_symbol.to_s.downcase
      str.tr!("@", "")
      str
    end
  end
end
