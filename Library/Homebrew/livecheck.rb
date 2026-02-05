# typed: strict
# frozen_string_literal: true

require "livecheck/constants"
require "livecheck/options"
require "cask/cask"

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

  # Options to modify livecheck's behavior.
  sig { returns(Homebrew::Livecheck::Options) }
  attr_reader :options

  # A very brief description of why the formula/cask/resource is skipped (e.g.
  # `No longer developed or maintained`).
  sig { returns(T.nilable(String)) }
  attr_reader :skip_msg

  # A block used by strategies to identify version information.
  sig { returns(T.nilable(Proc)) }
  attr_reader :strategy_block

  sig { params(package_or_resource: T.any(Cask::Cask, T.class_of(Formula), Resource)).void }
  def initialize(package_or_resource)
    @package_or_resource = package_or_resource
    @options = T.let(Homebrew::Livecheck::Options.new, Homebrew::Livecheck::Options)
    @referenced_cask_name = T.let(nil, T.nilable(String))
    @referenced_formula_name = T.let(nil, T.nilable(String))
    @regex = T.let(nil, T.nilable(Regexp))
    @skip = T.let(false, T::Boolean)
    @skip_msg = T.let(nil, T.nilable(String))
    @strategy = T.let(nil, T.nilable(Symbol))
    @strategy_block = T.let(nil, T.nilable(Proc))
    @throttle = T.let(nil, T.nilable(Integer))
    @url = T.let(nil, T.nilable(T.any(String, Symbol)))
  end

  # Sets the `@referenced_cask_name` instance variable to the provided `String`
  # or returns the `@referenced_cask_name` instance variable when no argument
  # is provided. Inherited livecheck values from the referenced cask
  # (e.g. regex) can be overridden in the `livecheck` block.
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
  # `String`/`Symbol` or returns the `@referenced_formula_name` instance
  # variable when no argument is provided. Inherited livecheck values from the
  # referenced formula (e.g. regex) can be overridden in the `livecheck` block.
  sig {
    params(
      # Name of formula to inherit livecheck info from.
      formula_name: T.any(String, Symbol),
    ).returns(T.nilable(T.any(String, Symbol)))
  }
  def formula(formula_name = T.unsafe(nil))
    case formula_name
    when nil
      @referenced_formula_name
    when String, :parent
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

  # Sets the `@throttle` instance variable to the provided `Integer` or returns
  # the `@throttle` instance variable when no argument is provided.
  sig {
    params(
      # Throttle rate of version patch number to use for bumpable versions.
      rate: Integer,
    ).returns(T.nilable(Integer))
  }
  def throttle(rate = T.unsafe(nil))
    case rate
    when nil
      @throttle
    when Integer
      @throttle = rate
    end
  end

  # Sets the `@url` instance variable to the provided argument or returns the
  # `@url` instance variable when no argument is provided. The argument can be
  # a `String` (a URL) or a supported `Symbol` corresponding to a URL in the
  # formula/cask/resource (e.g. `:stable`, `:homepage`, `:head`, `:url`).
  # Any options provided to the method are passed through to `Strategy` methods
  # (`page_headers`, `page_content`).
  sig {
    params(
      # URL to check for version information.
      url:           T.any(String, Symbol),
      cookies:       T.nilable(T::Hash[String, String]),
      header:        T.nilable(T.any(String, T::Array[String])),
      homebrew_curl: T.nilable(T::Boolean),
      post_form:     T.nilable(T::Hash[Symbol, String]),
      post_json:     T.nilable(T::Hash[Symbol, T.anything]),
      referer:       T.nilable(String),
      user_agent:    T.nilable(T.any(String, Symbol)),
    ).returns(T.nilable(T.any(String, Symbol)))
  }
  def url(
    url = T.unsafe(nil),
    cookies: nil,
    header: nil,
    homebrew_curl: nil,
    post_form: nil,
    post_json: nil,
    referer: nil,
    user_agent: nil
  )
    raise ArgumentError, "Only use `post_form` or `post_json`, not both" if post_form && post_json

    @options.cookies = cookies unless cookies.nil?
    @options.header = header unless header.nil?
    @options.homebrew_curl = homebrew_curl unless homebrew_curl.nil?
    @options.post_form = post_form unless post_form.nil?
    @options.post_json = post_json unless post_json.nil?
    @options.referer = referer unless referer.nil?
    @options.user_agent = user_agent unless user_agent.nil?

    case url
    when nil
      @url
    when String, :head, :homepage, :stable, :url
      @url = url
    when Symbol
      raise ArgumentError, "#{url.inspect} is not a valid URL shorthand"
    end
  end

  delegate url_options: :@options
  delegate arch: :@package_or_resource
  delegate os: :@package_or_resource
  delegate version: :@package_or_resource
  private :arch, :os, :version
  # Returns a `Hash` of all instance variable values.
  # @return [Hash]
  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash
    {
      "options"  => @options.to_hash,
      "cask"     => @referenced_cask_name,
      "formula"  => @referenced_formula_name,
      "regex"    => @regex,
      "skip"     => @skip,
      "skip_msg" => @skip_msg,
      "strategy" => @strategy,
      "throttle" => @throttle,
      "url"      => @url,
    }
  end
end
