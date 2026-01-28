# typed: strict
# frozen_string_literal: true

require "install"
require "utils/output"

module OS
  module Mac
    module Reinstall
      module ClassMethods
        extend T::Helpers
        include ::Utils::Output::Mixin

        requires_ancestor { ::Homebrew::Reinstall }

        sig { params(dry_run: T::Boolean).void }
        def reinstall_pkgconf_if_needed!(dry_run: false)
          mismatch = Homebrew::Pkgconf.macos_sdk_mismatch
          return unless mismatch

          if dry_run
            opoo "pkgconf would be reinstalled due to macOS version mismatch"
            return
          end

          pkgconf = ::Formula["pkgconf"]

          context = T.unsafe(self).build_install_context(pkgconf, flags: [])

          begin
            Homebrew::Install.fetch_formulae([context.formula_installer])
            T.unsafe(self).reinstall_formula(context)
            ohai "Reinstalled pkgconf due to macOS version mismatch"
          rescue
            ofail Homebrew::Pkgconf.mismatch_warning_message(mismatch)
          end
        end
      end
    end
  end
end

Homebrew::Reinstall.singleton_class.prepend(OS::Mac::Reinstall::ClassMethods)
