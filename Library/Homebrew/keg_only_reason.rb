# typed: strict
# frozen_string_literal: true

# Used to annotate formulae that duplicate macOS-provided software
# or cause conflicts when linked in.
class KegOnlyReason
  sig { returns(T.any(Symbol, String)) }
  attr_reader :reason

  sig { params(reason: T.any(Symbol, String), explanation: String).void }
  def initialize(reason, explanation)
    @reason = reason
    @explanation = explanation
  end

  sig { returns(T::Boolean) }
  def versioned_formula?
    @reason == :versioned_formula
  end

  sig { returns(T::Boolean) }
  def provided_by_macos?
    @reason == :provided_by_macos
  end

  sig { returns(T::Boolean) }
  def shadowed_by_macos?
    @reason == :shadowed_by_macos
  end

  sig { returns(T::Boolean) }
  def by_macos?
    provided_by_macos? || shadowed_by_macos?
  end

  sig { returns(T::Boolean) }
  def applicable?
    # macOS reasons aren't applicable on other OSs
    # (see extend/os/mac/keg_only_reason for override on macOS)
    !by_macos?
  end

  sig { returns(String) }
  def to_s
    return @explanation unless @explanation.empty?

    if versioned_formula?
      <<~EOS
        this is an alternate version of another formula
      EOS
    elsif provided_by_macos?
      <<~EOS
        macOS already provides this software and installing another version in
        parallel can cause all kinds of trouble
      EOS
    elsif shadowed_by_macos?
      <<~EOS
        macOS provides similar software and installing this software in
        parallel can cause all kinds of trouble
      EOS
    else
      @reason.to_s
    end.strip
  end

  sig { returns(T::Hash[String, String]) }
  def to_hash
    reason_string = if @reason.is_a?(Symbol)
      @reason.inspect
    else
      @reason.to_s
    end

    {
      "reason"      => reason_string,
      "explanation" => @explanation,
    }
  end
end

require "extend/os/keg_only_reason"
