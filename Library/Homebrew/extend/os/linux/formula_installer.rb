# typed: strict
# frozen_string_literal: true

class FormulaInstaller
  sig { params(formula: Formula).returns(T.nilable(T::Boolean)) }
  def fresh_install?(formula)
    !Homebrew::EnvConfig.developer? &&
      (!installed_as_dependency? || !formula.any_version_installed?)
  end
end
