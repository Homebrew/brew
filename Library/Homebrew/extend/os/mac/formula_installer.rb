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
          (installed_on_request? || !formula.any_version_installed?)
      end

      sig { void }
      def check_developer_tools_for_bottle_pour
        return unless ::Hardware::CPU.arm?
        return if formula.bottle_specification.skip_relocation?

        # TODO: Remove this check after pure-Ruby ad-hoc signing is released:
        # https://github.com/Homebrew/ruby-macho/pull/997
        # We need the developer tools for `codesign` when relocating bottles.
        require "diagnostic"
        unless (developer_tools_warning = ::Homebrew::Diagnostic::Checks.new.check_for_installed_developer_tools)
          return
        end

        ofail developer_tools_warning
        exit 1
      end
    end
  end
end

FormulaInstaller.prepend(OS::Mac::FormulaInstaller)
