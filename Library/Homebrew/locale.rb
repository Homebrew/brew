# typed: strict
# frozen_string_literal: true

# Representation of a system locale.
#
# Used to compare the system language and languages defined using the cask `language` stanza.
class Locale
  # Error when a string cannot be parsed to a `Locale`.
  class ParserError < StandardError
  end

  # ISO 639-1 or ISO 639-2
  LANGUAGE_REGEX = /(?:[a-z]{2,3})/
  private_constant :LANGUAGE_REGEX

  # ISO 15924
  SCRIPT_REGEX = /(?:[A-Z][a-z]{3})/
  private_constant :SCRIPT_REGEX

  # ISO 3166-1 or UN M.49
  REGION_REGEX = /(?:[A-Z]{2}|\d{3})/
  private_constant :REGION_REGEX

  LOCALE_REGEX = /\A((?:#{LANGUAGE_REGEX}|#{REGION_REGEX}|#{SCRIPT_REGEX})(?:-|$)){1,3}\Z/
  private_constant :LOCALE_REGEX

  sig { params(string: String).returns(T.attached_class) }
  def self.parse(string)
    if (locale = try_parse(string))
      return locale
    end

    raise ParserError, "'#{string}' cannot be parsed to a #{self}"
  end

  sig { params(string: String).returns(T.nilable(T.attached_class)) }
  def self.try_parse(string)
    return if string.blank?

    scanner = StringScanner.new(string)

    if (language = scanner.scan(LANGUAGE_REGEX))
      sep = scanner.scan("-")
      return if (sep && scanner.eos?) || (sep.nil? && !scanner.eos?)
    end

    if (script = scanner.scan(SCRIPT_REGEX))
      sep = scanner.scan("-")
      return if (sep && scanner.eos?) || (sep.nil? && !scanner.eos?)
    end

    region = scanner.scan(REGION_REGEX)

    return unless scanner.eos?

    new(language, script, region)
  end

  sig { returns(T.nilable(String)) }
  attr_reader :language

  sig { returns(T.nilable(String)) }
  attr_reader :script

  sig { returns(T.nilable(String)) }
  attr_reader :region

  sig { params(language: T.nilable(String), script: T.nilable(String), region: T.nilable(String)).void }
  def initialize(language, script, region)
    raise ArgumentError, "#{self.class} cannot be empty" if language.nil? && region.nil? && script.nil?

    unless language.nil?
      regex = LANGUAGE_REGEX
      raise ParserError, "'language' does not match #{regex}" unless language.match?(regex)

      @language = T.let(language, T.nilable(String))
    end

    unless script.nil?
      regex = SCRIPT_REGEX
      raise ParserError, "'script' does not match #{regex}" unless script.match?(regex)

      @script = T.let(script, T.nilable(String))
    end

    return if region.nil?

    regex = REGION_REGEX
    raise ParserError, "'region' does not match #{regex}" unless region.match?(regex)

    @region = T.let(region, T.nilable(String))
  end

  sig { params(other: T.any(String, Locale)).returns(T::Boolean) }
  def include?(other)
    unless other.is_a?(self.class)
      other = self.class.try_parse(other)
      return false if other.nil?
    end

    [:language, :script, :region].all? do |var|
      next true if other.public_send(var).nil?

      public_send(var) == other.public_send(var)
    end
  end

  sig { params(other: T.any(String, Locale)).returns(T::Boolean) }
  def eql?(other)
    unless other.is_a?(self.class)
      other = self.class.try_parse(other)
      return false if other.nil?
    end

    [:language, :script, :region].all? do |var|
      public_send(var) == other.public_send(var)
    end
  end
  alias == eql?

  sig {
    params(
      locale_groups: T::Enumerable[T::Enumerable[T.any(String, Locale)]],
    ).returns(
      T.nilable(T::Enumerable[T.any(String, Locale)]),
    )
  }
  def detect(locale_groups)
    locale_groups.find { |locales| locales.any? { |locale| eql?(locale) } } ||
      locale_groups.find { |locales| locales.any? { |locale| include?(locale) } }
  end

  sig { returns(String) }
  def to_s
    [@language, @script, @region].compact.join("-")
  end
end
