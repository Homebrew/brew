# typed: strict
# frozen_string_literal: true

require "utils/output"

module Cask
  class Reinstall
    extend ::Utils::Output::Mixin

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

      download_queue = Homebrew::DownloadQueue.new_if_concurrency_enabled(pour: true)
      cask_installers = casks.map do |cask|
        Installer.new(cask, binaries:, verbose:, force:, skip_cask_deps:, require_sha:, reinstall: true,
                      quarantine:, zap:, download_queue:)
      end

      if download_queue
        cask_installers.each(&:prelude)

        oh1 "Fetching downloads for: #{casks.map { |cask| Formatter.identifier(cask.full_name) }.to_sentence}",
            truncate: false
        cask_installers.each(&:enqueue_downloads)
        download_queue.fetch
      end

      exit 1 if Homebrew.failed?

      cask_installers.each(&:install)
    end
  end
end
