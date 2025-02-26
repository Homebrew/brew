# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Stop
      TRIGGERS = %w[stop unload terminate term t u].freeze

      def self.run(targets, verbose:, no_wait:, max_wait:)
        ServicesCli.check(targets) &&
          ServicesCli.stop(targets, verbose:, no_wait:, max_wait:)
      end
    end
  end
end
