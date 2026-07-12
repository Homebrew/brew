# typed: strict
# frozen_string_literal: true

class Pathname
  # A Pathname is blank if its path is empty. Unlike `Pathname#empty?`,
  # this never touches the filesystem, so an existing-but-empty file or
  # directory is still present.
  #
  # ```ruby
  # Pathname.new("").blank?     # => true
  # Pathname.new(" ").blank?    # => false
  # Pathname.new("test").blank? # => false
  # ```
  #
  # @see https://github.com/rails/rails/blob/main/activesupport/lib/active_support/core_ext/pathname/blank.rb
  #   `Pathname#blank?`
  sig { returns(T::Boolean) }
  def blank?
    to_s.empty?
  end

  sig { returns(T::Boolean) }
  def present? = !blank? # :nodoc:
end
