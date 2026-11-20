# typed: strict
# frozen_string_literal: true

require "utils/output"

module DeprecateDisable
  # Common implementation of the formula and cask lifecycle stanzas.
  module DSL
    extend T::Helpers

    requires_ancestor { Utils::Output::Mixin }

    StanzaArgs = T.type_alias { T::Hash[Symbol, T.nilable(T.any(String, Symbol))] }
    private_constant :StanzaArgs

    # The dates declared by the respective stanzas, if present.
    sig { returns(T.nilable(Date)) }
    attr_reader :deprecation_date, :disable_date

    # The reason for each active state. Either may be nil.
    sig { returns(T.nilable(T.any(String, Symbol))) }
    attr_reader :deprecation_reason, :disable_reason

    # The suggested replacements for each active state, if specified.
    sig { returns(T.nilable(String)) }
    attr_reader :deprecation_replacement_formula, :deprecation_replacement_cask,
                :disable_replacement_formula, :disable_replacement_cask

    # The original stanza arguments for API serialisation, including future dates.
    # @api private
    sig { returns(T.nilable(StanzaArgs)) }
    attr_reader :deprecate_args, :disable_args

    # A future disable date implies deprecation unless an explicit deprecation date is set.
    sig { returns(T::Boolean) }
    def deprecated? = @deprecated == true

    # Disablement takes precedence even when both predicates are true.
    sig { returns(T::Boolean) }
    def disabled? = @disabled == true

    private

    sig {
      params(date: String, because: T.nilable(T.any(String, Symbol)), replacement: T.nilable(String),
             replacement_formula: T.nilable(String), replacement_cask: T.nilable(String)).void
    }
    def set_deprecation(date:, because:, replacement:, replacement_formula:, replacement_cask:)
      formula, cask = lifecycle_replacements(:deprecate!, replacement, replacement_formula, replacement_cask)
      @deprecate_args = T.let({ date:, because:, replacement_formula:, replacement_cask: }, T.nilable(StanzaArgs))
      deprecation_date = Date.parse(date)
      @deprecation_date = T.let(deprecation_date, T.nilable(Date))
      if deprecation_date <= Date.today
        mark_deprecated(because, formula, cask)
      else
        # Clear any implicit deprecation from an earlier disable! stanza.
        @deprecated = false
        @deprecation_reason = nil
        @deprecation_replacement_formula = nil
        @deprecation_replacement_cask = nil
      end
    end

    sig {
      params(date: String, because: T.nilable(T.any(String, Symbol)), replacement: T.nilable(String),
             replacement_formula: T.nilable(String), replacement_cask: T.nilable(String)).void
    }
    def set_disable(date:, because:, replacement:, replacement_formula:, replacement_cask:)
      formula, cask = lifecycle_replacements(:disable!, replacement, replacement_formula, replacement_cask)
      @disable_args = T.let({ date:, because:, replacement_formula:, replacement_cask: }, T.nilable(StanzaArgs))
      disable_date = Date.parse(date)
      @disable_date = T.let(disable_date, T.nilable(Date))
      if disable_date > Date.today
        mark_deprecated(because, formula, cask) unless @deprecation_date
        return
      end

      @disabled = T.let(true, T.nilable(T::Boolean))
      @disable_reason = T.let(because, T.nilable(T.any(String, Symbol)))
      @disable_replacement_formula = T.let(formula, T.nilable(String))
      @disable_replacement_cask = T.let(cask, T.nilable(String))
    end

    sig { params(reason: T.nilable(T.any(String, Symbol)), formula: T.nilable(String), cask: T.nilable(String)).void }
    def mark_deprecated(reason, formula, cask)
      @deprecated = T.let(true, T.nilable(T::Boolean))
      @deprecation_reason = T.let(reason, T.nilable(T.any(String, Symbol)))
      @deprecation_replacement_formula = T.let(formula, T.nilable(String))
      @deprecation_replacement_cask = T.let(cask, T.nilable(String))
    end

    sig {
      params(stanza: Symbol, replacement: T.nilable(String), formula: T.nilable(String), cask: T.nilable(String))
        .returns([T.nilable(String), T.nilable(String)])
    }
    def lifecycle_replacements(stanza, replacement, formula, cask)
      if [replacement, formula, cask].filter_map(&:presence).length > 1
        raise ArgumentError, "more than one of replacement, replacement_formula and/or replacement_cask specified!"
      end

      if replacement
        odeprecated("#{stanza}(:replacement)", "#{stanza}(:replacement_formula) or #{stanza}(:replacement_cask)")
      end
      [formula.presence || replacement, cask.presence || replacement]
    end
  end
end
