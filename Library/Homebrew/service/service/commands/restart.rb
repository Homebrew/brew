# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Restart
      # NOTE: The restart command is used to update service files
      # after a package gets updated through `brew upgrade`.
      # This works by removing the old file with `brew services stop`
      # and installing the new one with `brew services start|run`.

      TRIGGERS = %w[restart relaunch reload r].freeze

      def self.run(targets, verbose:)
        return unless ServicesCli.check(targets)

        ran = []
        started = []
        targets.each do |service|
          if service.loaded? && !service.service_file_present?
            ran << service
          else
            # group not-started services with started ones for restart
            started << service
          end
          ServicesCli.stop([service], verbose:) if service.loaded?
        end

        ServicesCli.run(ran, verbose:) if ran.present?
        ServicesCli.start(started, verbose:) if started.present?
      end
    end
  end
end
