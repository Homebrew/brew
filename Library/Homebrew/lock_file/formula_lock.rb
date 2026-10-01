# typed: strict
# frozen_string_literal: true

# A lock file for a formula.
class FormulaLock < LockFile
  sig { params(rack_name: String).void }
  def initialize(rack_name)
    super(:formula, HOMEBREW_CELLAR/rack_name)
  end
end
