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
require "extend/blank/nil_class"
require "extend/blank/false_class"
require "extend/blank/true_class"
require "extend/blank/array"
require "extend/blank/hash"
require "extend/blank/symbol"
require "extend/blank/string"
require "extend/blank/numeric"
require "extend/blank/pathname"
require "extend/blank/time"
