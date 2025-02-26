# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Restart
      # NOTE: The restart command is used to update service files
      # after a package gets updated through `brew upgrade`.
      # This works by removing the old file with `brew services stop`
      # and installing the new one with `brew services start|run`.

      TRIGGERS = %w[restart relaunch reload r].freeze

      sig { params(targets: T::Array[Service::FormulaWrapper], verbose: T::Boolean).void }
      def self.run(targets, verbose:)
        return unless Homebrew::Cmd::Services.check(targets)

        ran = []
        started = []
        targets.each do |service|
          if service.loaded? && !service.service_file_present?
            ran << service
          else
            # group not-started services with started ones for restart
            started << service
          end
          Homebrew::Cmd::Services.stop([service], verbose:) if service.loaded?
        end

        Homebrew::Cmd::Services.run if ran.present?
        Homebrew::Cmd::Services.start(started, verbose:) if started.present?
      end
    end
  end
end
