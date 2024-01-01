# typed: true
# frozen_string_literal: true

module Cask
  #
  # @api private
  class Reinstall
    def self.reinstall_casks(
      *casks,
      verbose: nil,
      force: nil,
      skip_cask_deps: nil,
      binaries: nil,
      require_sha: nil,
      quarantine: nil,
      zap: nil
    )
      require "cask/installer"

      quarantine = true if quarantine.nil?

      casks.each do |cask|
        Installer.new(cask,
                      binaries:       binaries,
                      verbose:        verbose,
                      force:          force,
                      skip_cask_deps: skip_cask_deps,
                      require_sha:    require_sha,
                      reinstall:      true,
                      quarantine:     quarantine,
                      zap:            zap).install
      end
    end
  end
end
