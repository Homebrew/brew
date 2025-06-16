# typed: strict
# frozen_string_literal: true

module Enumerable
  # The negative of the {Enumerable#include?}. Returns `true` if the
  # collection does not include the object.
  sig { params(object: T.untyped).returns(T::Boolean) }
  def exclude?(object) = !include?(object)

  # Returns a new +Array+ without the blank items.
  # Uses Object#blank? for determining if an item is blank.
  #
  # ### Examples
  #
  # ```
  # [1, "", nil, 2, " ", [], {}, false, true].compact_blank
  # # =>  [1, 2, true]
  # ```
  #
  # ```ruby
  # Set.new([nil, "", 1, false]).compact_blank
  # # => [1]
  # ```
  #
  # When called on a {Hash}, returns a new {Hash} without the blank values.
  #
  # ```ruby
  # { a: "", b: 1, c: nil, d: [], e: false, f: true }.compact_blank
  # # => { b: 1, f: true }
  # ```
  sig { returns(T.self_type) }
  def compact_blank = T.unsafe(self).reject(&:blank?)
end

class Hash
  # {Hash#reject} has its own definition, so this needs one too.
  def compact_blank = reject { |_k, v| T.unsafe(v).blank? }
end
