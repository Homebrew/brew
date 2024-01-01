# typed: true
# frozen_string_literal: true

require "description_cache_store"

module Homebrew
  # Helper module for searching formulae or casks.
  #
  # @api private
  module Search
    def self.query_regexp(query)
      if (m = query.match(%r{^/(.*)/$}))
        Regexp.new(m[1])
      else
        query
      end
    rescue RegexpError
      raise "#{query} is not a valid regex."
    end

    def self.search_descriptions(string_or_regex, args, search_type: :desc)
      both = !args.formula? && !args.cask?
      eval_all = args.eval_all? || Homebrew::EnvConfig.eval_all?

      if args.formula? || both
        ohai "Formulae"
        CacheStoreDatabase.use(:descriptions) do |db|
          cache_store = DescriptionCacheStore.new(db)
          Descriptions.search(string_or_regex, search_type, cache_store, eval_all).print
        end
      end
      return if !args.cask? && !both

      puts if both

      ohai "Casks"
      CacheStoreDatabase.use(:cask_descriptions) do |db|
        cache_store = CaskDescriptionCacheStore.new(db)
        Descriptions.search(string_or_regex, search_type, cache_store, eval_all).print
      end
    end

    def self.search_formulae(string_or_regex)
      if string_or_regex.is_a?(String) && string_or_regex.match?(HOMEBREW_TAP_FORMULA_REGEX)
        return begin
          [Formulary.factory(string_or_regex).name]
        rescue FormulaUnavailableError
          []
        end
      end

      aliases = Formula.alias_full_names
      results = search(Formula.full_names + aliases, string_or_regex).sort
      results |= Formula.fuzzy_search(string_or_regex).map { |n| Formulary.factory(n).full_name }

      results.map do |name|
        formula, canonical_full_name = begin
          f = Formulary.factory(name)
          [f, f.full_name]
        rescue
          [nil, name]
        end

        # Ignore aliases from results when the full name was also found
        next if aliases.include?(name) && results.include?(canonical_full_name)

        if formula&.any_version_installed?
          pretty_installed(name)
        elsif formula.nil? || formula.valid_platform?
          name
        end
      end.compact
    end

    def self.search_casks(string_or_regex)
      if string_or_regex.is_a?(String) && string_or_regex.match?(HOMEBREW_TAP_CASK_REGEX)
        return begin
          [Cask::CaskLoader.load(string_or_regex).token]
        rescue Cask::CaskUnavailableError
          []
        end
      end

      cask_tokens = Tap.flat_map(&:cask_tokens).map do |c|
        next if c.start_with?("homebrew/cask/") && !Homebrew::EnvConfig.no_install_from_api?

        c.sub(%r{^homebrew/cask.*/}, "")
      end.compact
      cask_tokens |= Homebrew::API::Cask.all_casks.keys unless Homebrew::EnvConfig.no_install_from_api?

      results = search(cask_tokens, string_or_regex)
      results += DidYouMean::SpellChecker.new(dictionary: cask_tokens)
                                         .correct(string_or_regex)

      results.sort.map do |name|
        cask = Cask::CaskLoader.load(name)
        if cask.installed?
          pretty_installed(cask.full_name)
        else
          cask.full_name
        end
      end.uniq
    end

    def self.search_names(string_or_regex, args)
      both = !args.formula? && !args.cask?

      all_formulae = if args.formula? || both
        search_formulae(string_or_regex)
      else
        []
      end

      all_casks = if args.cask? || both
        search_casks(string_or_regex)
      else
        []
      end

      [all_formulae, all_casks]
    end

    def self.search(selectable, string_or_regex, &block)
      case string_or_regex
      when Regexp
        search_regex(selectable, string_or_regex, &block)
      else
        search_string(selectable, string_or_regex.to_str, &block)
      end
    end

    def self.simplify_string(string)
      string.downcase.gsub(/[^a-z\d]/i, "")
    end

    def self.search_regex(selectable, regex)
      selectable.select do |*args|
        args = yield(*args) if block_given?
        args = Array(args).flatten.compact
        args.any? { |arg| arg.match?(regex) }
      end
    end

    def self.search_string(selectable, string)
      simplified_string = simplify_string(string)
      selectable.select do |*args|
        args = yield(*args) if block_given?
        args = Array(args).flatten.compact
        args.any? { |arg| simplify_string(arg).include?(simplified_string) }
      end
    end
  end
end
