# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class PourBottleCheck
  include OnSystem::MacOSAndLinux

  def initialize(formula)
    @formula = formula
  end

  def reason(reason)
    @formula.pour_bottle_check_unsatisfied_reason = reason
  end

  def satisfy(&block)
    @formula.send(:define_method, :pour_bottle?, &block)
  end
end
