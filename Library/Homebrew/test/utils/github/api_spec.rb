# typed: strict
# frozen_string_literal: true

require "utils/github"

RSpec.describe GitHub::API do
  describe "::sleep_for_rate_limit" do
    it "sleeps for at least 1 second even if the rate limit has already reset" do
      exception = GitHub::API::RateLimitExceededError.new(
        "API rate limit exceeded", reset: Time.now.to_i - 10, resource: "core", limit: 5000
      )
      expect(described_class).to receive(:sleep).with(1)
      described_class.sleep_for_rate_limit(exception)
    end
  end
end
