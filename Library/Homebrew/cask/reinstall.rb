# typed: strict
# frozen_string_literal: true

require "utils/output"
require "install"
require "cask/installer"

module Cask
  class Reinstall
    extend ::Utils::Output::Mixin

    sig {
      params(
        casks: ::Cask::Cask, verbose: T::Boolean, force: T::Boolean, skip_cask_deps: T::Boolean, binaries: T::Boolean,
        require_sha: T::Boolean, zap: T::Boolean, skip_prefetch: T::Boolean,
        download_queue: T.nilable(Homebrew::DownloadQueue),
        cask_installers: T.nilable(T::Array[Installer])
      ).returns(T::Array[Cask])
    }
    def self.reinstall_casks(
      *casks,
      verbose: false,
      force: false,
      skip_cask_deps: false,
      binaries: false,
      require_sha: false,
      zap: false,
      skip_prefetch: false,
      download_queue: nil,
      cask_installers: nil
    )
      created_download_queue = T.let(false, T::Boolean)
      if download_queue.nil?
        if skip_prefetch
          download_queue = Homebrew::DownloadQueue.default
        else
          download_queue = Homebrew::DownloadQueue.new(pour: true)
          created_download_queue = true
        end
      end

      cask_installers = T.let(cask_installers || [], T::Array[Installer])
      begin
        if cask_installers.empty?
          cask_installers = casks.map do |cask|
            Installer.new(
              cask,
              binaries:,
              verbose:,
              force:,
              skip_cask_deps:,
              require_sha:,
              reinstall:      true,
              zap:,
              download_queue:,
              defer_fetch:    true,
            )
          end
        end

        unless skip_prefetch
          cask_installers = Homebrew::Install.enqueue_cask_installers(cask_installers)
          download_queue.fetch(heading: Homebrew::Install.combined_fetch_downloads_heading(
            cask_names: cask_installers.map { |installer| installer.cask.full_name },
          ))
          Homebrew::Install.fetch_cask_dependencies(cask_installers, download_queue:)
        end
      ensure
        download_queue.shutdown if created_download_queue
      end

      # Reinstall everything that did download and report each failure as it
      # happens, rather than aborting the whole run; the failures still exit
      # nonzero at the end.
      reinstalled_casks = T.let([], T::Array[Cask])
      cask_installers.each do |installer|
        installer.install
        reinstalled_casks << installer.cask
      rescue => e
        ofail "#{installer.cask.full_name}: #{e}"
      end
      reinstalled_casks
    end
  end
end
