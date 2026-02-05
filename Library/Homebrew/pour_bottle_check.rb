# typed: strict
# frozen_string_literal: true

class PourBottleCheck
  include OnSystem::MacOSAndLinux

  sig { params(formula: T.class_of(Formula)).void }
  def initialize(formula)
    @formula = formula
  end

  sig { params(reason: String).void }
  def reason(reason)
    @formula.pour_bottle_check_unsatisfied_reason = reason
  end

  sig { params(block: T.proc.void).void }
  def satisfy(&block)
    @formula.send(:define_method, :pour_bottle?, &block)
  end
end
