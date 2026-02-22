# typed: strict
# frozen_string_literal: true

require "homebrew"

module Utils
  # Removes the rightmost segment from the constant expression in the string.
  #
  #   deconstantize('Net::HTTP')   # => "Net"
  #   deconstantize('::Net::HTTP') # => "::Net"
  #   deconstantize('String')      # => ""
  #   deconstantize('::String')    # => ""
  #   deconstantize('')            # => ""
  #
  # See also #demodulize.
  # @see https://github.com/rails/rails/blob/b0dd7c7/activesupport/lib/active_support/inflector/methods.rb#L247-L258
  #   `ActiveSupport::Inflector.deconstantize`
  sig { params(path: String).returns(String) }
  def self.deconstantize(path)
    T.must(path[0, path.rindex("::") || 0]) # implementation based on the one in facets' Module#spacename
  end

  # Removes the module part from the expression in the string.
  #
  #   demodulize('ActiveSupport::Inflector::Inflections') # => "Inflections"
  #   demodulize('Inflections')                           # => "Inflections"
  #   demodulize('::Inflections')                         # => "Inflections"
  #   demodulize('')                                      # => ""
  #
  # See also #deconstantize.
  # @see https://github.com/rails/rails/blob/b0dd7c7/activesupport/lib/active_support/inflector/methods.rb#L230-L245
  #   `ActiveSupport::Inflector.demodulize`
  # @raise [ArgumentError] if the provided path is nil
  sig { params(path: T.nilable(String)).returns(String) }
  def self.demodulize(path)
    raise ArgumentError, "No constant path provided" if path.nil?

    if (i = path.rindex("::"))
      T.must(path[(i + 2)..])
    else
      path
    end
  end

  # A lightweight alternative to `ActiveSupport::Inflector.pluralize`:
  # Combines `stem` with the `singular` or `plural` suffix based on `count`.
  # Adds a prefix of the count value if `include_count` is set to true.
  sig {
    params(stem: String, count: Integer, plural: String, singular: String, include_count: T::Boolean).returns(String)
  }
  def self.pluralize(stem, count, plural: "s", singular: "", include_count: false)
    case stem
    when "formula"
      plural = "e"
    when "dependency", "try"
      stem = stem.delete_suffix("y")
      plural = "ies"
      singular = "y"
    end

    prefix = include_count ? "#{count} " : ""
    suffix = (count == 1) ? singular : plural
    "#{prefix}#{stem}#{suffix}"
  end

  sig { params(author: String).returns({ email: String, name: String }) }
  def self.parse_author!(author)
    match_data = /^(?<name>[^<]+?)[ \t]*<(?<email>[^>]+?)>$/.match(author)
    if match_data
      name = match_data[:name]
      email = match_data[:email]
    end
    raise UsageError, "Unable to parse name and email." if name.blank? && email.blank?

    { name: T.must(name), email: T.must(email) }
  end

  # Makes an underscored, lowercase form from the expression in the string.
  #
  # Changes '::' to '/' to convert namespaces to paths.
  #
  #   underscore('ActiveModel')         # => "active_model"
  #   underscore('ActiveModel::Errors') # => "active_model/errors"
  #
  # @see https://github.com/rails/rails/blob/v6.1.7.2/activesupport/lib/active_support/inflector/methods.rb#L81-L100
  #   `ActiveSupport::Inflector.underscore`
  sig { params(camel_cased_word: T.any(String, Symbol)).returns(String) }
  def self.underscore(camel_cased_word)
    return camel_cased_word.to_s unless /[A-Z-]|::/.match?(camel_cased_word)

    word = camel_cased_word.to_s.gsub("::", "/")
    word.gsub!(/([A-Z])(?=[A-Z][a-z])|([a-z\d])(?=[A-Z])/) do
      T.must(::Regexp.last_match(1) || ::Regexp.last_match(2)) << "_"
    end
    word.tr!("-", "_")
    word.downcase!
    word
  end

  SAFE_FILENAME_REGEX = /[[:cntrl:]#{Regexp.escape("#{File::SEPARATOR}#{File::ALT_SEPARATOR}")}]/o
  private_constant :SAFE_FILENAME_REGEX

  sig { params(basename: String).returns(T::Boolean) }
  def self.safe_filename?(basename)
    !SAFE_FILENAME_REGEX.match?(basename)
  end

  sig { params(basename: String).returns(String) }
  def self.safe_filename(basename)
    basename.gsub(SAFE_FILENAME_REGEX, "")
  end

  # Converts a string starting with `:` to a symbol, otherwise returns the
  # string itself.
  #
  #   convert_to_string_or_symbol(":example") # => :example
  #   convert_to_string_or_symbol("example")  # => "example"
  sig { params(string: String).returns(T.any(String, Symbol)) }
  def self.convert_to_string_or_symbol(string)
    return T.must(string[1..]).to_sym if string.start_with?(":")

    string
  end

  sig { params(obj: T.untyped).returns(T.untyped) }
  def self.deep_stringify_symbols(obj)
    case obj
    when String
      # Escape leading : or \ to avoid confusion with stringified symbols
      # ":foo" -> "\:foo"
      # "\foo" -> "\\foo"
      if obj.start_with?(":", "\\")
        "\\#{obj}"
      else
        obj
      end
    when Symbol
      ":#{obj}"
    when Hash
      obj.to_h { |k, v| [deep_stringify_symbols(k), deep_stringify_symbols(v)] }
    when Array
      obj.map { |v| deep_stringify_symbols(v) }
    else
      obj
    end
  end

  sig { params(obj: T.untyped).returns(T.untyped) }
  def self.deep_unstringify_symbols(obj)
    case obj
    when String
      if obj.start_with?("\\")
        obj[1..]
      elsif obj.start_with?(":")
        T.must(obj[1..]).to_sym
      else
        obj
      end
    when Hash
      obj.to_h { |k, v| [deep_unstringify_symbols(k), deep_unstringify_symbols(v)] }
    when Array
      obj.map { |v| deep_unstringify_symbols(v) }
    else
      obj
    end
  end

  sig {
    type_parameters(:U)
      .params(obj: T.all(T.type_parameter(:U), Object))
      .returns(T.nilable(T.type_parameter(:U)))
  }
  def self.deep_compact_blank(obj)
    obj = case obj
    when Hash
      obj.transform_values { |v| deep_compact_blank(v) }
         .compact
    when Array
      obj.filter_map { |v| deep_compact_blank(v) }
    else
      obj
    end

    return if obj.blank? || (obj.is_a?(Numeric) && obj.zero?)

    obj
  end
end
