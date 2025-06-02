# typed: strict
# frozen_string_literal: true

module DinrusBrew
  module API
    # Helper functions for using the analytics JSON API.
    module Analytics
      class << self
        sig { returns(String) }
        def analytics_api_path
          "analytics"
        end
        alias generic_analytics_api_path analytics_api_path

        sig { params(category: String, days: T.any(Integer, String)).returns(T::Hash[String, T.untyped]) }
        def fetch(category, days)
          DinrusBrew::API.fetch "#{analytics_api_path}/#{category}/#{days}d.json"
        end
      end
    end
  end
end
