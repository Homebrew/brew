# typed: strict
# frozen_string_literal: true

module Cask
  class Uninstall
    sig { params(casks: ::Cask::Cask, binaries: T::Boolean, force: T::Boolean, verbose: T::Boolean).void }
    def self.uninstall_casks(*casks, binaries: false, force: false, verbose: false)
      require "cask/installer"

      casks.each do |cask|
        odebug "Uninstalling Cask #{cask}"

        raise CaskNotInstalledError, cask if !cask.installed? && !force

        Installer.new(cask, binaries:, force:, verbose:).uninstall
      end
    end
  end
end
