# frozen_string_literal: true

module Bundler
  class SimilarityDetector
    SimilarityScore = Struct.new(:string, :distance)

    # initialize with an array of words to be matched against
    def initialize(corpus)
      @corpus = corpus
    end

    # return an array of words similar to 'word' from the corpus
    def similar_words(word, limit = 3)
      words_by_similarity = @corpus.map {|w| SimilarityScore.new(w, levenshtein_distance(word, w)) }
      words_by_similarity.select {|s| s.distance <= limit }.sort_by(&:distance).map(&:string)
    end

    # return the result of 'similar_words', concatenated into a list
    # (eg "a, b, or c")
    def similar_word_list(word, limit = 3)
      words = similar_words(word, limit)
      if words.length == 1
        words[0]
      elsif words.length > 1
        [words[0..-2].join(", "), words[-1]].join(" or ")
      end
    end

    protected

    # https://www.informit.com/articles/article.aspx?p=683059&seqNum=36
    def levenshtein_distance(this, that, ins = 2, del = 2, sub = 1)
      # ins, del, sub are weighted costs
      return nil if this.nil?
      return nil if that.nil?
      dm = [] # distance matrix

      # Initialize first row values
      dm[0] = (0..this.length).collect {|i| i * ins }
      fill = [0] * (this.length - 1)

      # Initialize first column values
      (1..that.length).each do |i|
        dm[i] = [i * del, fill.flatten]
      end

      # populate matrix
      (1..that.length).each do |i|
        (1..this.length).each do |j|
          # critical comparison
          dm[i][j] = [
            dm[i - 1][j - 1] + (this[j - 1] == that[i - 1] ? 0 : sub),
            dm[i][j - 1] + ins,
            dm[i - 1][j] + del,
          ].min
        end
      end

      # The last value in matrix is the Levenshtein distance between the strings
      dm[that.length][this.length]
    end
  end
end
