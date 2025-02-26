# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Run
      TRIGGERS = ["run"].freeze

      def self.run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.run(targets, verbose:)
      end
    end
  end
end
