# typed: strict
# frozen_string_literal: true

require "description_cache_store"
require "utils/output"

module Homebrew
  # Helper module for searching formulae or casks.
  module Search
    extend Utils::Output::Mixin

    QUERY_REGEX = %r{^/(.*)/$}

    SearchBlockType = T.type_alias do
      T.nilable(
        T.proc
         .params(arg0: T.any(T::Array[String], T::Array[T::Array[String]]))
         .returns(T.nilable(T.any(String, T::Array[String]))),
      )
    end

    SearchResultType = T.type_alias do
      T.any(
        T::Array[String],
        T::Array[T::Array[String]],
        T::Hash[String, T.nilable(String)],
        T::Hash[String, T::Array[T.nilable(String)]],
      )
    end

    SelectableType = T.type_alias do
      # These must define a `select` method that takes a block and returns an array or hash.
      # Since sorbet has minimal support for overloading sig, the return type must be casted to the actual type.
      # DescriptionCacheStore and Hash instances will return a Hash, other types will return an Array.
      T.any(DescriptionCacheStore, SearchResultType)
    end

    sig { params(query: String).returns(T.any(Regexp, String)) }
    def self.query_regexp(query)
      if (regex = query[QUERY_REGEX, 1])
        Regexp.new(regex)
      else
        query
      end
    rescue RegexpError
      raise "#{query} is not a valid regex."
    end

    sig { params(_cask: Cask::Cask).returns(T::Boolean) }
    def self.ignore_cask?(_cask) = false

    T::Sig::WithoutRuntime.sig {
      params(
        string_or_regex: T.any(Regexp, String),
        # These must define `cask?` and `formula?` methods.
        # Since only one command is typically loaded at a time, this alias is not expected to be available at runtime.
        args:            T.any(Homebrew::Cmd::Desc::Args, Homebrew::Cmd::SearchCmd::Args),
        search_type:     T.nilable(Descriptions::SearchField),
        show_missing:    T::Boolean,
      ).void
    }
    def self.search_descriptions(string_or_regex, args, search_type: nil, show_missing: false)
      require "descriptions"

      search_type ||= Descriptions::SearchField::Description
      both = !args.formula? && !args.cask?

      if args.formula? || both
        ohai "Formulae"
        CacheStoreDatabase.use(:descriptions) do |db|
          cache_store = DescriptionCacheStore.new(T.cast(db, CacheStoreDatabase[String, T.anything]))
          Descriptions.search(string_or_regex, search_type, cache_store).print
        end
      end
      return if !args.cask? && !both

      puts if both

      ohai "Casks"
      CacheStoreDatabase.use(:cask_descriptions) do |db|
        cache_store = CaskDescriptionCacheStore.new(T.cast(db, CacheStoreDatabase[String, T.anything]))
        Descriptions.search(string_or_regex, search_type, cache_store).print(show_missing:)
      end
    end

    sig { params(string_or_regex: T.any(Regexp, String)).returns(T::Array[String]) }
    def self.search_formulae(string_or_regex)
      if string_or_regex.is_a?(String) && string_or_regex.match?(HOMEBREW_TAP_FORMULA_REGEX)
        return begin
          [Formulary.factory(string_or_regex).name]
        rescue FormulaUnavailableError
          []
        end
      end

      aliases = Formula.alias_full_names
      results = T.cast(search(Formula.full_names + aliases, string_or_regex), T::Array[String]).sort
      if string_or_regex.is_a?(String)
        results |= Formula.fuzzy_search(string_or_regex).map do |n|
          Formulary.factory(n).full_name
        end
      end

      results.filter_map do |name|
        formula, canonical_full_name = begin
          f = Formulary.factory(name)
          [f, f.full_name]
        rescue
          [nil, name]
        end

        # Ignore aliases from results when the full name was also found
        next if aliases.include?(name) && results.include?(canonical_full_name)

        installed = formula&.any_version_installed? == true
        next if formula && !formula.valid_platform? && !installed

        pretty_install_status(
          name,
          installed:,
          deprecated:       formula&.deprecated? == true,
          disabled:         formula&.disabled? == true,
          mark_uninstalled: false,
        )
      end
    end

    sig { params(string_or_regex: T.any(Regexp, String)).returns(T::Array[String]) }
    def self.search_casks(string_or_regex)
      require "cask/cask_loader"

      if string_or_regex.is_a?(String) && string_or_regex.match?(HOMEBREW_TAP_CASK_REGEX)
        return begin
          matched_cask = Cask::CaskLoader.load(string_or_regex)
          ignore_cask?(matched_cask) ? [] : [matched_cask.token]
        rescue Cask::CaskUnavailableError
          []
        end
      end

      cask_tokens = Tap.each_with_object([]) do |tap, array|
        # We can exclude the core cask tap because `CoreCaskTap#cask_tokens` returns short names by default.
        if tap.official? && !tap.core_cask_tap?
          tap.cask_tokens.each { |token| array << token.sub(%r{^homebrew/cask.*/}, "") }
        else
          tap.cask_tokens.each { |token| array << token }
        end
      end.uniq

      results = T.cast(search(cask_tokens, string_or_regex), T::Array[String])
      if string_or_regex.is_a?(String)
        results += DidYouMean::SpellChecker.new(dictionary: cask_tokens)
                                           .correct(string_or_regex)
      end

      results.sort.filter_map do |name|
        cask = Cask::CaskLoader.load(name.to_s)
        next if ignore_cask?(cask)

        pretty_install_status(
          cask.full_name,
          installed:        cask.installed?,
          deprecated:       cask.deprecated?,
          disabled:         cask.disabled?,
          mark_uninstalled: false,
        )
      rescue Homebrew::UntrustedTapError
        nil
      end.uniq
    end

    T::Sig::WithoutRuntime.sig {
      params(
        string_or_regex: T.any(Regexp, String),
        # These must define `cask?`, and `formula?` methods.
        # Since only one command is typically loaded at a time, this alias is not expected to be available at runtime.
        args:            T.any(Homebrew::Cmd::Desc::Args, Homebrew::Cmd::InstallCmd::Args, Homebrew::Cmd::SearchCmd::Args),
      ).returns([T::Array[String], T::Array[String]])
    }
    def self.search_names(string_or_regex, args)
      if !args.formula? && !args.cask? # both
        [search_formulae(string_or_regex), search_casks(string_or_regex)]
      elsif args.formula?
        [search_formulae(string_or_regex), []]
      elsif args.cask?
        [[], search_casks(string_or_regex)]
      else
        [[], []]
      end
    end

    sig {
      params(selectable: SelectableType, string_or_regex: T.any(Regexp, String), block: SearchBlockType)
        .returns(SearchResultType)
    }
    def self.search(selectable, string_or_regex, &block)
      case string_or_regex
      when Regexp
        search_regex(selectable, string_or_regex, &block)
      else
        search_string(selectable, string_or_regex.to_str, &block)
      end
    end

    sig { params(string: String).returns(String) }
    def self.simplify_string(string)
      string.downcase.gsub(/[^a-z\d@+]/i, "")
    end

    sig { params(selectable: SelectableType, regex: Regexp, _block: SearchBlockType).returns(SearchResultType) }
    def self.search_regex(selectable, regex, &_block)
      selectable.select do |*args|
        args = yield(*args) if block_given?
        args = Array(args).flatten.compact
        args.any? { |arg| arg.match?(regex) }
      end
    end

    sig { params(selectable: SelectableType, string: String, _block: SearchBlockType).returns(SearchResultType) }
    def self.search_string(selectable, string, &_block)
      simplified_string = simplify_string(string)
      selectable.select do |*args|
        args = yield(*args) if block_given?
        args = Array(args).flatten.compact
        args.any? { |arg| simplify_string(arg).include?(simplified_string) }
      end
    end
  end
end

require "extend/os/search"
