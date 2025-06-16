# typed: strong
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # The interface for livecheck strategies. Because third-party strategies
    # are not required to extend this module, we do not provide any default
    # method implementations here.
    module Strategic
      extend T::Helpers
      interface!

      # Whether the strategy can be applied to the provided URL.
      #
      # @param url [String] the URL to match against
      sig { abstract.params(url: String).returns(T::Boolean) }
      def match?(url); end

      # Checks the content at the URL for new versions. Implementations may not
      # support all options.
      #
      # @param url the URL of the content to check
      # @param regex a regex for matching versions in content
      # @param provided_content content to check instead of
      #   fetching
      # @param options options to modify behavior
      # @param block a block to match the content
      sig {
        abstract.params(
          url:              String,
          regex:            T.nilable(Regexp),
          provided_content: T.nilable(String),
          options:          Options,
          block:            T.nilable(Proc),
        ).returns(T::Hash[Symbol, T.anything])
      }
      def find_versions(url:, regex: nil, provided_content: nil, options: Options.new, &block); end
    end
  end
end
