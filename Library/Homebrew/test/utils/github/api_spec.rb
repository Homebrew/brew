# typed: strict
# frozen_string_literal: true

require "utils/github"

RSpec.describe GitHub::API do
  describe "::github_cli_token" do
    it "uses the selected executable and timeout without printing lookup output" do
      expect(described_class).to receive(:system_command).with(
        Pathname("/trusted/bin/gh"), args: %w[auth token --hostname github.com],
        env: Utils::Path.formula_opt_bin_env("gh"), timeout: 10, print_stderr: false, debug: false, verbose: false
      ).and_return(instance_double(SystemCommand::Result,
                                   to_a: ["test-token\n", "", instance_double(Process::Status, success?: true)]))

      described_class.github_cli_token(executable: Pathname("/trusted/bin/gh"), timeout: 10)
    end
  end

  it "optionally returns response headers for cursor pagination" do
    allow(described_class).to receive(:credentials).and_return(nil)
    allow(Utils::Curl).to receive(:curl_output) do |*args, **|
      File.write(args.fetch(args.index("--dump-header").to_i + 1),
                 "HTTP/2 200\r\nLink: <https://api.github.com/next>; rel=\"next\"\r\n")
      instance_double(SystemCommand::Result, stdout: "[]\n200",
                                             status: instance_double(Process::Status, success?: true))
    end

    expect(described_class.open_rest("https://api.github.com/example", return_headers: true))
      .to match([[], include('Link: <https://api.github.com/next>; rel="next"')])
  end

  it "recognises secondary limits and honours Retry-After on primary limits" do
    allow(Time).to receive(:now).and_return(Time.at(1000))
    limits = [
      ["403", "retry-after: 120\r\n", "You have exceeded a secondary rate limit."],
      ["403", "", "You have exceeded a secondary rate limit."],
      ["429", "x-ratelimit-remaining: 0\r\nx-ratelimit-reset: 1120\r\n" \
              "x-ratelimit-resource: core\r\nx-ratelimit-limit: 5000\r\nretry-after: 180\r\n", "Rate limit exceeded"],
    ].map do |status, headers, message|
      described_class.raise_error({ message: }.to_json, "", status, headers, [])
    rescue GitHub::API::RateLimitExceededError => e
      e.reset
    end

    expect(limits).to eq([1120, 1060, 1180])
  end

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
