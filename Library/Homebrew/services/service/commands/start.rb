# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Start
      TRIGGERS = %w[start launch load s l].freeze

      sig {
        params(targets: T::Array[Service::FormulaWrapper], custom_plist: T.nilable(String),
               verbose: T.nilable(T::Boolean)).void
      }
      def self.run(targets, custom_plist, verbose:)
        Service::ServicesCli.check(targets)
        Service::ServicesCli.start(targets, custom_plist, verbose:)
      end
    end
  end
end
