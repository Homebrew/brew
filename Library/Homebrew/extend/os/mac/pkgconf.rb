# typed: strict
# frozen_string_literal: true

module Homebrew
  module Pkgconf
    module_function

    sig { returns(T.nilable([String, String])) }
    def macos_sdk_mismatch
      # We don't provide suitable bottles for these versions.
      return if OS::Mac.version.prerelease? || OS::Mac.version.outdated_release?

      pkgconf = begin
        ::Formulary.factory_stub("pkgconf")
      rescue FormulaUnavailableError
        nil
      end
      return unless pkgconf&.any_version_installed?

      tab = Tab.for_formula(pkgconf)
      return unless tab.built_on

      built_on_version = tab.built_on["os_version"]
                            &.delete_prefix("macOS ")
                            &.sub(/\.\d+$/, "")
      return unless built_on_version

      current_version = MacOS.version.to_s
      return if built_on_version == current_version

      [built_on_version, current_version]
    end

    sig { params(mismatch: [String, String]).returns(String) }
    def mismatch_warning_message(mismatch)
      <<~EOS
        You have pkgconf installed that was built on macOS #{mismatch[0]},
                 but you are running macOS #{mismatch[1]}.

        This can cause issues with packages that depend on system libraries, such as libffi.
        To fix this issue, reinstall pkgconf:
          brew reinstall pkgconf

        For more information, see: https://github.com/Homebrew/brew/issues/16137
      EOS
    end
  end
end
