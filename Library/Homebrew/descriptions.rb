# typed: strict
# frozen_string_literal: true

require "formula"
require "formula_versions"
require "search"

# Helper class for printing and searching descriptions.
class Descriptions
  # Enum for specifying which fields to search.
  class SearchField < T::Enum
    enums do
      # enum values are not mutable, and calling .freeze on them breaks Sorbet
      # rubocop:disable Style/MutableConstant
      Name = new
      Description = new
      Either = new
      # rubocop:enable Style/MutableConstant
    end
  end

  # Given a regex, find all formulae whose specified fields contain a match.
  sig {
    params(
      string_or_regex: T.any(Regexp, String),
      field:           SearchField,
      cache_store:     T.any(DescriptionCacheStore, T::Hash[String, String], T::Hash[String, T::Array[T.nilable(String)]]),
      eval_all:        T::Boolean,
    ).returns(T.attached_class)
  }
  def self.search(string_or_regex, field, cache_store, eval_all = Homebrew::EnvConfig.eval_all?)
    cache_store.populate_if_empty!(eval_all:) if cache_store.is_a?(DescriptionCacheStore)

    results = case field
    when SearchField::Name
      Homebrew::Search.search(cache_store, string_or_regex) { |name, _| name }
    when SearchField::Description
      Homebrew::Search.search(cache_store, string_or_regex) { |_, desc| desc }
    when SearchField::Either
      Homebrew::Search.search(cache_store, string_or_regex)
    else
      T.absurd(field)
    end

    new(T.cast(results, T.any(T::Hash[String, String], T::Hash[String, T::Array[String]])))
  end

  # Create an actual instance.
  sig { params(descriptions: T.any(T::Hash[String, String], T::Hash[String, T::Array[String]])).void }
  def initialize(descriptions)
    @descriptions = T.let(descriptions, T.any(T::Hash[String, String], T::Hash[String, T::Array[String]]))
  end

  # Take search results -- a hash mapping formula names to descriptions -- and
  # print them.
  sig { void }
  def print
    blank = Formatter.warning("[no description]")
    @descriptions.keys.sort.each do |full_name|
      short_name = short_names[full_name]
      printed_name = if short_name && short_name_counts[short_name] == 1
        short_name
      else
        full_name
      end
      description = @descriptions[full_name] || blank
      if description.is_a?(Array)
        names = description[0]
        description = description[1] || blank
        puts "#{Tty.bold}#{printed_name}:#{Tty.reset} (#{names}) #{description}"
      else
        puts "#{Tty.bold}#{printed_name}:#{Tty.reset} #{description}"
      end
    end
  end

  private

  sig { returns(T::Hash[String, String]) }
  def short_names
    @short_names ||= T.let(
      @descriptions.keys.to_h { |k| [k, k.split("/").fetch(-1)] },
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { returns(T::Hash[String, Integer]) }
  def short_name_counts
    @short_name_counts ||= T.let(
      short_names.values
                 .each_with_object(Hash.new(0)) do |name, counts|
        counts[name] += 1
      end,
      T.nilable(T::Hash[String, Integer]),
    )
  end
end
