# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Kill
      TRIGGERS = %w[kill k].freeze

      def self.run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.kill(targets, verbose:)
      end
    end
  end
end
