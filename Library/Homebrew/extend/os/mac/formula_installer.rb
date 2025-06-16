# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module FormulaInstaller
      extend T::Helpers

      requires_ancestor { ::FormulaInstaller }

      sig { params(formula: Formula).returns(T.nilable(T::Boolean)) }
      def fresh_install?(formula)
        !::Homebrew::EnvConfig.developer? && !OS::Mac.version.outdated_release? &&
          (!installed_as_dependency? || !formula.any_version_installed?)
      end
    end
  end
end

FormulaInstaller.prepend(OS::Mac::FormulaInstaller)
