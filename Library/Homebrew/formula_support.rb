# typed: true
# frozen_string_literal: true

# Used to track formulae that cannot be installed at the same time.
FormulaConflict = Struct.new(:name, :reason)

# Used to annotate formulae that duplicate macOS-provided software
# or cause conflicts when linked in.
class KegOnlyReason
  attr_reader :reason

  def initialize(reason, explanation)
    @reason = reason
    @explanation = explanation
  end

  def versioned_formula?
    @reason == :versioned_formula
  end

  def provided_by_macos?
    @reason == :provided_by_macos
  end

  def shadowed_by_macos?
    @reason == :shadowed_by_macos
  end

  def by_macos?
    provided_by_macos? || shadowed_by_macos?
  end

  sig { returns(T::Boolean) }
  def applicable?
    # macOS reasons aren't applicable on other OSs
    # (see extend/os/mac/formula_support for override on macOS)
    !by_macos?
  end

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
      @reason
    end.strip
  end

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

require "extend/os/formula_support"
