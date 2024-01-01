# typed: true
# frozen_string_literal: true

module Cask
  # @api private
  class Uninstall
    def self.uninstall_casks(*casks, binaries: nil, force: false, verbose: false)
      require "cask/installer"

      casks.each do |cask|
        odebug "Uninstalling Cask #{cask}"

        raise CaskNotInstalledError, cask if !cask.installed? && !force

        Installer.new(cask, binaries: binaries, force: force, verbose: verbose).uninstall
      end
    end
  end
end
