# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Start
      TRIGGERS = %w[start launch load s l].freeze

      def self.run(targets, custom_plist, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.start(targets, custom_plist, verbose:)
      end
    end
  end
end
