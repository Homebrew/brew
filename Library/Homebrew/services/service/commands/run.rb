# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Run
      TRIGGERS = ["run"].freeze

      sig { params(targets: T::Array[Service::FormulaWrapper], verbose: T.nilable(T::Boolean)).void }
      def self.run(targets, verbose:)
        Service::ServicesCli.check(targets)
        Service::ServicesCli.run(targets, verbose:)
      end
    end
  end
end
