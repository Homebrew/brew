require_relative "../spell_checker"

module DidYouMean
  class KeyErrorChecker
    def initialize(key_error)
      @key = key_error.key
      @keys = key_error.receiver.keys
    end

    def corrections
      @corrections ||= exact_matches.empty? ? SpellChecker.new(dictionary: @keys).correct(@key).map(&:inspect) : exact_matches
    end

    private

    def exact_matches
      @exact_matches ||= @keys.select { |word| @key == word.to_s }.map(&:inspect)
    end
  end
end
