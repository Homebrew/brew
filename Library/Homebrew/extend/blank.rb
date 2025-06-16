# typed: strict
# frozen_string_literal: true

class Object
  # An object is blank if it's false, empty, or a whitespace string.
  #
  # For example, `nil`, `''`, `'   '`, `[]`, `{}` and `false` are all blank.
  #
  # ### Example
  #
  # ```ruby
  # !address || address.empty?
  # ```
  #
  # can be simplified to
  #
  # ```ruby
  # address.blank?
  # ```
  sig { returns(T::Boolean) }
  def blank?
    respond_to?(:empty?) ? !!T.unsafe(self).empty? : false
  end

  # An object is present if it's not blank.
  sig { returns(T::Boolean) }
  def present? = !blank?

  # Returns the receiver if it's present, otherwise returns `nil`.
  #
  # `object.presence` is equivalent to `object.present? ? object : nil`.
  #
  # ### Example
  #
  # ```ruby
  # state   = params[:state]   if params[:state].present?
  # country = params[:country] if params[:country].present?
  # region  = state || country || 'US'
  # ```
  #
  # can be simplified to
  #
  # ```ruby
  # region = params[:state].presence || params[:country].presence || 'US'
  # ```
  sig { returns(T.nilable(T.self_type)) }
  def presence
    self if present?
  end
end

class NilClass
  # `nil` is blank:
  #
  # ```ruby
  # nil.blank? # => true
  # ```
  sig { returns(TrueClass) }
  def blank? = true

  sig { returns(FalseClass) }
  def present? = false # :nodoc:
end

class FalseClass
  # `false` is blank:
  #
  # ```ruby
  # false.blank? # => true
  # ```
  sig { returns(TrueClass) }
  def blank? = true

  sig { returns(FalseClass) }
  def present? = false # :nodoc:
end

class TrueClass
  # `true` is not blank:
  #
  # ```ruby
  # true.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true # :nodoc:
end

class Array
  # An array is blank if it's empty:
  #
  # ```ruby
  # [].blank?      # => true
  # [1,2,3].blank? # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end

class Hash
  # A hash is blank if it's empty:
  #
  #
  # ```ruby
  # {}.blank?                # => true
  # { key: 'value' }.blank?  # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end

class Symbol
  # A Symbol is blank if it's empty:
  #
  # ```ruby
  # :''.blank?     # => true
  # :symbol.blank? # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end

class String
  BLANK_RE = /\A[[:space:]]*\z/
  # This is a cache that is intentionally mutable
  # rubocop:disable Style/MutableConstant
  ENCODED_BLANKS_ = T.let(Hash.new do |h, enc|
    h[enc] = Regexp.new(BLANK_RE.source.encode(enc), BLANK_RE.options | Regexp::FIXEDENCODING)
  end, T::Hash[Encoding, Regexp])
  # rubocop:enable Style/MutableConstant

  # A string is blank if it's empty or contains whitespaces only:
  #
  # ```ruby
  # ''.blank?       # => true
  # '   '.blank?    # => true
  # "\t\n\r".blank? # => true
  # ' blah '.blank? # => false
  # ```
  #
  # Unicode whitespace is supported:
  #
  # ```ruby
  # "\u00a0".blank? # => true
  # ```
  sig { returns(T::Boolean) }
  def blank?
    # The regexp that matches blank strings is expensive. For the case of empty
    # strings we can speed up this method (~3.5x) with an empty? call. The
    # penalty for the rest of strings is marginal.
    empty? ||
      begin
        BLANK_RE.match?(self)
      rescue Encoding::CompatibilityError
        T.must(ENCODED_BLANKS_[encoding]).match?(self)
      end
  end

  sig { returns(T::Boolean) }
  def present? = !blank? # :nodoc:
end

class Numeric # :nodoc:
  # No number is blank:
  #
  # ```ruby
  # 1.blank? # => false
  # 0.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true
end

class Time # :nodoc:
  # No Time is blank:
  #
  # ```ruby
  # Time.now.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true
end
