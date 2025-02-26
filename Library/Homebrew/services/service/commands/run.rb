# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Run
      TRIGGERS = ["run"].freeze

      sig { params(targets: T::Array[Service::FormulaWrapper], verbose: T::Boolean).void }
      def self.run(targets, verbose:)
        Homebrew::Cmd::Services.check(targets) &&
          Homebrew::Cmd::Services.run
      end
    end
  end
end
