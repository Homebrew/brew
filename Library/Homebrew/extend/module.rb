# typed: strict
# frozen_string_literal: true

class Module
  include T::Sig

  # The inverse of <tt>Module#include?</tt>. Returns true if the module
  # does not include the other module.
  sig { params(mod: T::Module[T.anything]).returns(T::Boolean) }
  def exclude?(mod) = !include?(mod)
end
