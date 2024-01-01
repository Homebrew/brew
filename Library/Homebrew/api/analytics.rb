# typed: true
# frozen_string_literal: true

module Homebrew
  module API
    # Helper functions for using the analytics JSON API.
    #
    # @api private
    module Analytics
      class << self
        sig { returns(String) }
        def analytics_api_path
          "analytics"
        end
        alias generic_analytics_api_path analytics_api_path

        sig { params(category: String, days: T.any(Integer, String)).returns(Hash) }
        def fetch(category, days)
          Homebrew::API.fetch "#{analytics_api_path}/#{category}/#{days}d.json"
        end
      end
    end
  end
end
