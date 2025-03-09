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

      sig { params(targets: T::Array[Service::FormulaWrapper], verbose: T.nilable(T::Boolean)).returns(NilClass) }
      def self.run(targets, verbose:)
        Service::ServicesCli.check(targets)

        ran = []
        started = []
        targets.each do |service|
          if service.loaded? && !service.service_file_present?
            ran << service
          else
            # group not-started services with started ones for restart
            started << service
          end
          Service::ServicesCli.stop([service], verbose:) if service.loaded?
        end

        Service::ServicesCli.run(targets, verbose:) if ran.present?
        Service::ServicesCli.start(started, verbose:) if started.present?
        nil
      end
    end
  end
end
