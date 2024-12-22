# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "formula"
require "formula_versions"
require "search"

# Helper class for printing and searching descriptions.
class Descriptions
  # Given a regex, find all formulae whose specified fields contain a match.
  def self.search(string_or_regex, field, cache_store,
                  eval_all = Homebrew::EnvConfig.eval_all?, cache_store_hash: false)
    cache_store.populate_if_empty!(eval_all:) unless cache_store_hash

    results = case field
    when :name
      Homebrew::Search.search(cache_store, string_or_regex) { |name, _| name }
    when :desc
      Homebrew::Search.search(cache_store, string_or_regex) { |_, desc| desc }
    when :either
      Homebrew::Search.search(cache_store, string_or_regex)
    end

    new(results)
  end

  # Create an actual instance.
  def initialize(descriptions)
    @descriptions = descriptions
  end

  # Take search results -- a hash mapping formula names to descriptions -- and
  # print them.
  def print
    blank = Formatter.warning("[no description]")
    @descriptions.keys.sort.each do |full_name|
      short_name = short_names[full_name]
      printed_name = if short_name_counts[short_name] == 1
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

  def short_names
    @short_names ||= @descriptions.keys.to_h { |k| [k, k.split("/").last] }
  end

  def short_name_counts
    @short_name_counts ||=
      short_names.values
                 .each_with_object(Hash.new(0)) do |name, counts|
        counts[name] += 1
      end
  end
end
