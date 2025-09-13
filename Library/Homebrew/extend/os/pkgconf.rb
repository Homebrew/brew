# typed: strict
# frozen_string_literal: true

module Homebrew
  module Pkgconf
    module_function

    sig { returns(T.nilable(T::Hash[Symbol, String])) }
    def macos_sdk_mismatch
      return unless OS.mac?

      # We don't provide suitable bottles for these versions.
      return if OS::Mac.version.prerelease? || OS::Mac.version.outdated_release?

      pkgconf = begin
        ::Formula["pkgconf"]
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

      { built_on_version: built_on_version, current_version: current_version }
    end

    sig { params(mismatch: T::Hash[Symbol, String]).returns(String) }
    def mismatch_warning_message(mismatch)
      return "" unless OS.mac?

      <<~EOS
        You have pkgconf installed that was built on macOS #{mismatch[:built_on_version]}
                 but you are running macOS #{mismatch[:current_version]}.

        This can cause issues with packages that depend on system libraries, such as libffi.
        To fix this issue, reinstall pkgconf:
          brew reinstall pkgconf

        For more information, see: https://github.com/Homebrew/brew/issues/16137
      EOS
    end
  end
end
