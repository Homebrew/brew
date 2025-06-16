# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Bundle
      module ClassMethods
        sig { returns(T::Boolean) }
        def mas_installed?
          false
        end

        # Setup pkg-config, if present, to help locate packages
        # Only need this on Linux as Homebrew provides a shim on macOS
        sig { void }
        def prepend_pkgconf_path_if_needed!
          pkgconf = Formulary.factory("pkgconf")
          return unless pkgconf.any_version_installed?

          ENV.prepend_path "PATH", pkgconf.opt_bin.to_s
        end
      end
    end
  end
end

Homebrew::Bundle.singleton_class.prepend(OS::Linux::Bundle::ClassMethods)
