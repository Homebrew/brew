# frozen_string_literal: true

module DidYouMean
  # spell checker for a dictionary that has a tree
  # structure, see doc/tree_spell_checker_api.md
  class TreeSpellChecker
    attr_reader :dictionary, :separator, :augment

    def initialize(dictionary:, separator: '/', augment: nil)
      @dictionary = dictionary
      @separator = separator
      @augment = augment
    end

    def correct(input)
      plausibles = plausible_dimensions(input)
      return fall_back_to_normal_spell_check(input) if plausibles.empty?

      suggestions = find_suggestions(input, plausibles)
      return fall_back_to_normal_spell_check(input) if suggestions.empty?

      suggestions
    end

    def dictionary_without_leaves
      @dictionary_without_leaves ||= dictionary.map { |word| word.split(separator)[0..-2] }.uniq
    end

    def tree_depth
      @tree_depth ||= dictionary_without_leaves.max { |a, b| a.size <=> b.size }.size
    end

    def dimensions
      @dimensions ||= tree_depth.times.map do |index|
                        dictionary_without_leaves.map { |element| element[index] }.compact.uniq
                      end
    end

    def find_leaves(path)
      path_with_separator = "#{path}#{separator}"

      dictionary
        .select {|str| str.include?(path_with_separator) }
        .map {|str| str.gsub(path_with_separator, '') }
    end

    def plausible_dimensions(input)
      input.split(separator)[0..-2]
        .map
        .with_index { |element, index| correct_element(dimensions[index], element) if dimensions[index] }
        .compact
    end

    def possible_paths(states)
      states.map { |state| state.join(separator) }
    end

    private

    def find_suggestions(input, plausibles)
      states = plausibles[0].product(*plausibles[1..-1])
      paths  = possible_paths(states)
      leaf   = input.split(separator).last

      find_ideas(paths, leaf)
    end

    def fall_back_to_normal_spell_check(input)
      return [] unless augment

      ::DidYouMean::SpellChecker.new(dictionary: dictionary).correct(input)
    end

    def find_ideas(paths, leaf)
      paths.flat_map do |path|
        names = find_leaves(path)
        ideas = correct_element(names, leaf)

        ideas_to_paths(ideas, leaf, names, path)
      end.compact
    end

    def ideas_to_paths(ideas, leaf, names, path)
      if ideas.empty?
        nil
      elsif names.include?(leaf)
        ["#{path}#{separator}#{leaf}"]
      else
        ideas.map {|str| "#{path}#{separator}#{str}" }
      end
    end

    def correct_element(names, element)
      return names if names.size == 1

      str = normalize(element)

      return [str] if names.include?(str)

      ::DidYouMean::SpellChecker.new(dictionary: names).correct(str)
    end

    def normalize(str)
      str.downcase!
      str.tr!('@', ' ') if str.include?('@')
      str
    end
  end
end
