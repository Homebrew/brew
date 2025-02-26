# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Kill
      TRIGGERS = %w[kill k].freeze

      sig { params(targets: T::Array[Service::FormulaWrapper], verbose: T.nilable(T::Boolean)).void }
      def self.run(targets, verbose:)
        Service::ServicesCli.check(targets)
        Service::ServicesCli.kill(targets, verbose:)
      end
    end
  end
end
