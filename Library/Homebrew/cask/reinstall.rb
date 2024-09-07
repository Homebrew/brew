# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Cask
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
                      binaries:,
                      verbose:,
                      force:,
                      skip_cask_deps:,
                      require_sha:,
                      reinstall:      true,
                      quarantine:,
                      zap:).install
      end
    end
  end
end
