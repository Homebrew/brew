# typed: true
# frozen_string_literal: true

require "livecheck/constants"

# The {Livecheck} class implements the DSL methods used in a formula's, cask's
# or resource's `livecheck` block and stores related instance variables. Most
# of these methods also return the related instance variable when no argument
# is provided.
#
# This information is used by the `brew livecheck` command to control its
# behavior. Example `livecheck` blocks can be found in the
# [`brew livecheck` documentation](https://docs.brew.sh/Brew-Livecheck).
class Livecheck
  extend Forwardable

  # A very brief description of why the formula/cask/resource is skipped (e.g.
  # `No longer developed or maintained`).
  sig { returns(T.nilable(String)) }
  attr_reader :skip_msg

  sig { params(package_or_resource: T.any(Cask::Cask, T.class_of(Formula), Resource)).void }
  def initialize(package_or_resource)
    @package_or_resource = package_or_resource
    @referenced_cask_name = nil
    @referenced_formula_name = nil
    @regex = nil
    @skip = false
    @skip_msg = nil
    @strategy = nil
    @strategy_block = nil
    @url = nil
  end

  # Sets the `@referenced_cask_name` instance variable to the provided `String`
  # or returns the `@referenced_cask_name` instance variable when no argument
  # is provided. Inherited livecheck values from the referenced cask
  # (e.g. regex) can be overridden in the livecheck block.
  sig {
    params(
      # Name of cask to inherit livecheck info from.
      cask_name: String,
    ).returns(T.nilable(String))
  }
  def cask(cask_name = T.unsafe(nil))
    case cask_name
    when nil
      @referenced_cask_name
    when String
      @referenced_cask_name = cask_name
    end
  end

  # Sets the `@referenced_formula_name` instance variable to the provided
  # `String` or returns the `@referenced_formula_name` instance variable when
  # no argument is provided. Inherited livecheck values from the referenced
  # formula (e.g. regex) can be overridden in the livecheck block.
  sig {
    params(
      # Name of formula to inherit livecheck info from.
      formula_name: String,
    ).returns(T.nilable(String))
  }
  def formula(formula_name = T.unsafe(nil))
    case formula_name
    when nil
      @referenced_formula_name
    when String
      @referenced_formula_name = formula_name
    end
  end

  # Sets the `@regex` instance variable to the provided `Regexp` or returns the
  # `@regex` instance variable when no argument is provided.
  sig {
    params(
      # Regex to use for matching versions in content.
      pattern: Regexp,
    ).returns(T.nilable(Regexp))
  }
  def regex(pattern = T.unsafe(nil))
    case pattern
    when nil
      @regex
    when Regexp
      @regex = pattern
    end
  end

  # Sets the `@skip` instance variable to `true` and sets the `@skip_msg`
  # instance variable if a `String` is provided. `@skip` is used to indicate
  # that the formula/cask/resource should be skipped and the `skip_msg` very
  # briefly describes why it is skipped (e.g. "No longer developed or
  # maintained").
  sig {
    params(
      # String describing why the formula/cask is skipped.
      skip_msg: String,
    ).returns(T::Boolean)
  }
  def skip(skip_msg = T.unsafe(nil))
    @skip_msg = skip_msg if skip_msg.is_a?(String)

    @skip = true
  end

  # Should `livecheck` skip this formula/cask/resource?
  sig { returns(T::Boolean) }
  def skip?
    @skip
  end

  # Sets the `@strategy` instance variable to the provided `Symbol` or returns
  # the `@strategy` instance variable when no argument is provided. The strategy
  # symbols use snake case (e.g. `:page_match`) and correspond to the strategy
  # file name.
  sig {
    params(
      # Symbol for the desired strategy.
      symbol: Symbol,
      block:  T.nilable(Proc),
    ).returns(T.nilable(Symbol))
  }
  def strategy(symbol = T.unsafe(nil), &block)
    @strategy_block = block if block

    case symbol
    when nil
      @strategy
    when Symbol
      @strategy = symbol
    end
  end

  sig { returns(T.nilable(Proc)) }
  attr_reader :strategy_block

  # Sets the `@url` instance variable to the provided argument or returns the
  # `@url` instance variable when no argument is provided. The argument can be
  # a `String` (a URL) or a supported `Symbol` corresponding to a URL in the
  # formula/cask/resource (e.g. `:stable`, `:homepage`, `:head`, `:url`).
  sig {
    params(
      # URL to check for version information.
      url: T.any(String, Symbol),
    ).returns(T.nilable(T.any(String, Symbol)))
  }
  def url(url = T.unsafe(nil))
    case url
    when nil
      @url
    when String, :head, :homepage, :stable, :url
      @url = url
    when Symbol
      raise ArgumentError, "#{url.inspect} is not a valid URL shorthand"
    end
  end

  delegate version: :@package_or_resource
  delegate arch: :@package_or_resource
  private :version, :arch

  # Returns a `Hash` of all instance variable values.
  # @return [Hash]
  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash
    {
      "cask"     => @referenced_cask_name,
      "formula"  => @referenced_formula_name,
      "regex"    => @regex,
      "skip"     => @skip,
      "skip_msg" => @skip_msg,
      "strategy" => @strategy,
      "url"      => @url,
    }
  end
end
