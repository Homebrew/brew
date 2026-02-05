# typed: strict
# frozen_string_literal: true

class KegOnlyReason
  sig { returns(T::Boolean) }
  def applicable?
    true
  end
end
