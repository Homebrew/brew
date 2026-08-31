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

      sig { params(formula: Formula).returns(String) }
      def source_install_guidance(formula)
        return super unless ::Hardware::CPU.intel?

        <<~EOS
          Homebrew bottles are being phased out for Intel macOS.
          You can still try to install from source with:
            brew install --build-from-source #{formula}

          For details and updates on this policy, see:
            #{Formatter.url("https://github.com/orgs/Homebrew/discussions/7044")}

          This is a Tier 3 configuration:
            #{Formatter.url("https://docs.brew.sh/Support-Tiers#tier-3")}
          #{Formatter.bold("Do not report any issues to Homebrew/* repositories!")}
          Read the above document instead before opening any issues or PRs.
        EOS
      end
    end
  end
end

FormulaInstaller.prepend(OS::Mac::FormulaInstaller)
