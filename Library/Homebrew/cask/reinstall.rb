# typed: strict
# frozen_string_literal: true

module Cask
  class Reinstall
    sig {
      params(
        casks: ::Cask::Cask, verbose: T::Boolean, force: T::Boolean, skip_cask_deps: T::Boolean, binaries: T::Boolean,
        require_sha: T::Boolean, quarantine: T::Boolean, zap: T::Boolean
      ).void
    }
    def self.reinstall_casks(
      *casks,
      verbose: false,
      force: false,
      skip_cask_deps: false,
      binaries: false,
      require_sha: false,
      quarantine: false,
      zap: false
    )
      require "cask/installer"

      quarantine = true if quarantine.nil?

      casks.each do |cask|
        Installer
          .new(cask, binaries:, verbose:, force:, skip_cask_deps:, require_sha:, reinstall: true, quarantine:, zap:)
          .install
      end
    end
  end
end
