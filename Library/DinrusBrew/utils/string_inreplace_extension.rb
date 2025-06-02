# typed: strong
# frozen_string_literal: true

# Used by the {Utils::Inreplace.inreplace} function.
class StringInreplaceExtension
  sig { returns(T::Array[String]) }
  attr_accessor :errors

  sig { returns(String) }
  attr_accessor :inreplace_string

  sig { params(string: String).void }
  def initialize(string)
    @inreplace_string = string
    @errors = T.let([], T::Array[String])
  end

  # Same as `String#sub!`, but warns if nothing was replaced.
  #
  # @api public
  sig { params(before: T.any(Regexp, String), after: String, audit_result: T::Boolean).returns(T.nilable(String)) }
  def sub!(before, after, audit_result: true)
    result = inreplace_string.sub!(before, after)
    errors << "expected replacement of #{before.inspect} with #{after.inspect}" if audit_result && result.nil?
    result
  end

  # Same as `String#gsub!`, but warns if nothing was replaced.
  #
  # @api public
  sig {
    params(
      before:           T.any(Pathname, Regexp, String),
      after:            T.any(Pathname, String),
      old_audit_result: T.nilable(T::Boolean),
      audit_result:     T::Boolean,
    ).returns(T.nilable(String))
  }
  def gsub!(before, after, old_audit_result = nil, audit_result: true)
    # NOTE: must check for `#nil?` and not `#blank?`, or else `old_audit_result = false` will not call `odeprecated`.
    unless old_audit_result.nil?
      odeprecated "gsub!(before, after, #{old_audit_result})",
                  "gsub!(before, after, audit_result: #{old_audit_result})"
      audit_result = old_audit_result
    end
    before = before.to_s if before.is_a?(Pathname)
    result = inreplace_string.gsub!(before, after.to_s)
    errors << "expected replacement of #{before.inspect} with #{after.inspect}" if audit_result && result.nil?
    result
  end

  # Looks for Makefile style variable definitions and replaces the
  # value with "new_value", or removes the definition entirely.
  #
  # @api public
  sig { params(flag: String, new_value: T.any(String, Pathname)).void }
  def change_make_var!(flag, new_value)
    return if gsub!(/^#{Regexp.escape(flag)}[ \t]*[\\?+:!]?=[ \t]*((?:.*\\\n)*.*)$/,
                    "#{flag}=#{new_value}",
                    audit_result: false)

    errors << "expected to change #{flag.inspect} to #{new_value.inspect}"
  end

  # Removes variable assignments completely.
  #
  # @api public
  sig { params(flags: T.any(String, T::Array[String])).void }
  def remove_make_var!(flags)
    Array(flags).each do |flag|
      # Also remove trailing \n, if present.
      next if gsub!(/^#{Regexp.escape(flag)}[ \t]*[\\?+:!]?=(?:.*\\\n)*.*$\n?/,
                    "",
                    audit_result: false)

      errors << "expected to remove #{flag.inspect}"
    end
  end

  # Finds the specified variable.
  #
  # @api public
  sig { params(flag: String).returns(String) }
  def get_make_var(flag)
    T.must(inreplace_string[/^#{Regexp.escape(flag)}[ \t]*[\\?+:!]?=[ \t]*((?:.*\\\n)*.*)$/, 1])
  end
end
