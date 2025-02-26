# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Start
      TRIGGERS = %w[start launch load s l].freeze

      sig {
        params(targets: T::Array[Service::FormulaWrapper], custom_plist: T.nilable(String), verbose: T::Boolean).void
      }
      def self.run(targets, custom_plist, verbose:)
        Homebrew::Cmd::Services.check(targets) &&
          Homebrew::Cmd::Services.start(targets, custom_plist, verbose:)
      end
    end
  end
end
