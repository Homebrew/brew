# typed: strict
# frozen_string_literal: true

require "formula"
require "search"
require "cask/cask_loader"

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
      cache_store:     T.any(DescriptionCacheStore, T::Hash[String, T.nilable(String)],
                             T::Hash[String, T::Array[T.nilable(String)]]),
      status_data:     T::Hash[String, T::Hash[Symbol, T::Boolean]],
      eval_all:        T::Boolean,
    ).returns(T.attached_class)
  }
  def self.search(string_or_regex, field, cache_store, status_data: {}, eval_all: Homebrew::EnvConfig.eval_all?)
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

    results = T.cast(results, T.any(T::Hash[String, T.nilable(String)], T::Hash[String, T::Array[T.nilable(String)]]))

    new(results, status_data: status_data.slice(*results.keys))
  end

  # Create an actual instance.
  sig {
    params(
      descriptions: T.any(T::Hash[String, T.nilable(String)], T::Hash[String, T::Array[T.nilable(String)]]),
      status_data:  T::Hash[String, T::Hash[Symbol, T::Boolean]],
    ).void
  }
  def initialize(descriptions, status_data: {})
    @descriptions = T.let(
      descriptions,
      T.any(T::Hash[String, T.nilable(String)], T::Hash[String, T::Array[T.nilable(String)]]),
    )
    @status_data = T.let(status_data, T::Hash[String, T::Hash[Symbol, T::Boolean]])
  end

  # Take search results -- a hash mapping formula names to descriptions -- and
  # print them.
  sig { void }
  def print
    @descriptions.keys.sort.each do |full_name|
      description = @descriptions[full_name]
      next if description.nil?

      short_name = short_names[full_name]
      display_name = if short_name && short_name_counts[short_name] == 1
        short_name
      else
        full_name
      end
      display_name = decorate_name(full_name, display_name, description)
      if description.is_a?(Array)
        names = description[0]
        next if description[1].nil?

        description = T.must(description[1])
        puts names.present? ? "#{display_name}: (#{names}) #{description}" : "#{display_name}: #{description}"
      else
        puts "#{display_name}: #{description}"
      end
    end
  end

  private

  sig {
    params(
      full_name:    String,
      printed_name: String,
      description:  T.nilable(T.any(String, T::Array[T.nilable(String)])),
    ).returns(String)
  }
  def decorate_name(full_name, printed_name, description)
    return printed_name unless $stdout.tty?

    installed = if description.is_a?(Array)
      installed_casks.include?(full_name)
    else
      installed_formulae.include?(full_name)
    end
    printed_name = if installed
      Homebrew::Search.pretty_installed(printed_name)
    else
      "#{Tty.bold}#{printed_name}#{Tty.reset}"
    end

    status_data = @status_data[full_name]
    if status_data&.[](:deprecated)
      Homebrew::Search.pretty_deprecated(printed_name)
    elsif status_data&.[](:disabled)
      Homebrew::Search.pretty_disabled(printed_name)
    else
      formula_or_cask = begin
        Formulary.factory(full_name)
      rescue FormulaUnavailableError
        Cask::CaskLoader.load(full_name)
      rescue Cask::CaskUnavailableError
        nil
      end
      return printed_name if formula_or_cask.nil?

      if formula_or_cask.deprecated?
        Homebrew::Search.pretty_deprecated(printed_name)
      elsif formula_or_cask.disabled?
        Homebrew::Search.pretty_disabled(printed_name)
      else
        printed_name
      end
    end
  end

  sig { returns(T::Set[String]) }
  def installed_formulae
    @installed_formulae ||= T.let(
      Formula.installed.flat_map { |formula| [formula.name, formula.full_name] }.to_set,
      T.nilable(T::Set[String]),
    )
  end

  sig { returns(T::Set[String]) }
  def installed_casks
    @installed_casks ||= T.let(
      Cask::Caskroom.casks.flat_map { |cask| [cask.token, cask.full_name] }.to_set,
      T.nilable(T::Set[String]),
    )
  end

  sig { returns(T::Hash[String, String]) }
  def short_names
    @short_names ||= T.let(
      @descriptions.keys.to_h { |k| [k, Utils.name_from_full_name(k)] },
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { returns(T::Hash[String, Integer]) }
  def short_name_counts
    @short_name_counts ||= T.let(
      short_names.values
                 .tally,
      T.nilable(T::Hash[String, Integer]),
    )
  end
end
