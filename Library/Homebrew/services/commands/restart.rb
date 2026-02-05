# typed: strict
# frozen_string_literal: true

require "services/cli"

module Homebrew
  module Services
    module Commands
      module Restart
        # NOTE: The restart command is used to update service files
        # after a package gets updated through `brew upgrade`.
        # This works by removing the old file with `brew services stop`
        # and installing the new one with `brew services start|run`.

        TRIGGERS = %w[restart relaunch reload r].freeze

        sig {
          params(
            targets:      T::Array[Services::FormulaWrapper],
            custom_plist: T.nilable(String),
            verbose:      T::Boolean,
          ).void
        }
        def self.run(targets, custom_plist, verbose:)
          Services::Cli.check!(targets)

          ran = []
          started = []
          targets.each do |service|
            if service.loaded? && !service.service_file_present?
              ran << service
            else
              # group not-started services with started ones for restart
              started << service
            end
            Services::Cli.stop([service], verbose:) if service.loaded?
          end

          Services::Cli.run(targets, custom_plist, verbose:) if ran.present?
          Services::Cli.start(started, custom_plist, verbose:) if started.present?
        end
      end
    end
  end
end
