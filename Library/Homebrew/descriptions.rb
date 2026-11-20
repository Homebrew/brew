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
    ).returns(T.attached_class)
  }
  def self.search(string_or_regex, field, cache_store, status_data: {})
    cache_store.populate_if_empty! if cache_store.is_a?(DescriptionCacheStore)

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
    @installed_formulae = T.let(nil, T.nilable(T::Set[String]))
    @installed_casks = T.let(nil, T.nilable(T::Set[String]))
    @short_names = T.let(nil, T.nilable(T::Hash[String, String]))

    @descriptions = descriptions
    @status_data = status_data
  end

  # Take search results -- a hash mapping formula names to descriptions -- and
  # print them.
  sig { params(show_missing: T::Boolean).void }
  def print(show_missing: false)
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
        description = description.fetch(1, nil)
        next if description.nil? && !show_missing

        description ||= Formatter.warning("[no description]")
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
    deprecated = @status_data.dig(full_name, :deprecated) == true
    disabled = @status_data.dig(full_name, :disabled) == true
    if !deprecated && !disabled
      formula_or_cask = begin
        if description.is_a?(Array)
          Cask::CaskLoader.load(full_name)
        else
          Formulary.factory(full_name)
        end
      rescue FormulaUnavailableError, Cask::CaskUnavailableError
        nil
      end
      deprecated = formula_or_cask&.deprecated? == true
      disabled = formula_or_cask&.disabled? == true
    end

    Homebrew::Search.pretty_install_status(printed_name, installed:, deprecated:, disabled:, bold: true)
  end

  sig { returns(T::Set[String]) }
  def installed_formulae
    @installed_formulae ||= Formula.installed.flat_map { |formula| [formula.name, formula.full_name] }.to_set
  end

  sig { returns(T::Set[String]) }
  def installed_casks
    @installed_casks ||= Cask::Caskroom.casks.flat_map { |cask| [cask.token, cask.full_name] }.to_set
  end

  sig { returns(T::Hash[String, String]) }
  def short_names
    @short_names ||= @descriptions.keys.to_h { |k| [k, Utils.name_from_full_name(k)] }
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
