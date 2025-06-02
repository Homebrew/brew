# frozen_string_literal: true

module Bundler
  class Resolver
    class Incompatibility < PubGrub::Incompatibility
      attr_reader :extended_explanation

      def initialize(terms, cause:, custom_explanation: nil, extended_explanation: nil)
        @extended_explanation = extended_explanation

        super(terms, cause: cause, custom_explanation: custom_explanation)
      end
    end
  end
end
