# typed: strict
# frozen_string_literal: true

require "diagnostic"
require "utils/curl"

RSpec.describe Homebrew::Diagnostic::Checks do
  describe "#check_github_api_tokens" do
    sig { returns(Homebrew::Diagnostic::Checks) }
    subject(:checks) { described_class.new }

    before do
      %w[GH_TOKEN GITHUB_TOKEN HOMEBREW_GITHUB_API_TOKEN].each { ENV.delete(it) }
      allow(Utils::Curl).to receive(:curl_version).and_return(Version.new("7.54.1"))
    end

    it "reports that HOMEBREW_GITHUB_API_TOKEN is not passed to older curl" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "test-token"

      expect(checks.check_github_api_tokens&.to_s).to eq <<~EOS.rstrip
        GitHub API tokens are set, but curl 7.54.1 is older than 7.55.0.
        Homebrew does not pass these tokens to curl. Requests use unauthenticated
        rate limits and cannot access private repositories or write to GitHub.

        Upgrade curl to 7.55.0 or newer to use GitHub API tokens.
      EOS
    end

    it "does not warn when HOMEBREW_GITHUB_API_TOKEN is empty" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = ""

      expect(checks.check_github_api_tokens).to be_nil
    end

    test_each(%w[GH_TOKEN GITHUB_TOKEN]) do |variable|
      it "ignores #{variable}" do
        ENV[variable] = "test-token"

        expect(checks.check_github_api_tokens).to be_nil
      end
    end

    it "does not warn when no token variables are set" do
      expect(checks.check_github_api_tokens).to be_nil
    end

    it "does not warn with curl 7.55.0" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "test-token"
      allow(Utils::Curl).to receive(:curl_version).and_return(Version.new("7.55.0"))

      expect(checks.check_github_api_tokens).to be_nil
    end
  end

  describe "#check_tools" do
    sig { returns(Homebrew::Diagnostic::Checks) }
    subject(:checks) { described_class.new }

    sig { returns(Pathname) }
    let(:prefix) { mktmpdir }

    before do
      ENV["HOMEBREW_PREFIX"] = prefix.to_s
      ENV["HOMEBREW_CACHE"] = HOMEBREW_CACHE.to_s
      ENV["HOMEBREW_MINIMUM_CURL_VERSION"] = "7.41.0"
      %w[git curl].each do |tool|
        ENV.delete("HOMEBREW_FORCE_BREWED_#{tool.upcase}")
        ENV["HOMEBREW_#{tool.upcase}_PATH"] = ENV.fetch("HOMEBREW_#{tool.upcase}")
        executable = prefix/"opt/#{tool}/bin/#{tool}"
        executable.dirname.mkpath
        (executable.dirname/"version").write "999.0.0\n"
        executable.write <<~SH
          #!/bin/bash
          echo probe >> "#{executable.dirname}/probes"
          [[ -f "#{executable.dirname}/broken" ]] && exit 1
          printf '%s ' '#{(tool == "git") ? "git version" : "curl"}'
          cat "#{executable.dirname}/version"
        SH
        executable.chmod(0755)
      end
      checks.check_tools
      %w[git curl].each { |tool| (prefix/"opt/#{tool}/bin/probes").unlink }
    end

    after do
      Utils::Git.clear_available_cache
      Utils::Curl.clear_path_cache
    end

    it "checks each cached selection once when both tools work" do
      expect([checks.check_tools, *%w[git curl].map { |tool| (prefix/"opt/#{tool}/bin/probes").read.lines.length }])
        .to eq([[], 1, 1])
    end

    test_each(%w[git curl]) do |tool|
      it "reselects #{tool} after a cached executable stops working" do
        (prefix/"opt/#{tool}/bin/broken").write ""

        expect([checks.check_tools, ENV.fetch("HOMEBREW_#{tool.upcase}").start_with?(prefix.to_s),
                (prefix/"opt/#{tool}/bin/probes").read.lines.length]).to eq([[], false, 2])
      end

      it "reselects #{tool} when its reported version becomes too old" do
        (prefix/"opt/#{tool}/bin/version").write "1.0.0\n"

        expect([checks.check_tools, ENV.fetch("HOMEBREW_#{tool.upcase}").start_with?(prefix.to_s)])
          .to eq([[], false])
      end
    end

    it "reports failed checks after exactly one retry and leaves their caches invalidated" do
      result = instance_double(SystemCommand::Result, success?: false, stdout: "")
      expect(checks).to receive(:system_command).exactly(4).times.and_return(result)

      expect([checks.check_tools.length, *%w[git curl].map { |tool| (HOMEBREW_CACHE/"tool-selection"/tool).exist? }])
        .to eq([2, false, false])
    end

    it "discards the inherited curl version when both checks fail" do
      allow(checks).to receive(:system_command).and_raise(Timeout::Error)

      expect { checks.check_tools }.to change { ENV.fetch("HOMEBREW_CURL_VERSION", nil) }.from("999.0.0").to(nil)
    end

    it "retries timed-out checks once before reporting failure" do
      expect(checks).to receive(:system_command).exactly(4).times.and_raise(Timeout::Error)

      expect(checks.check_tools.map(&:text)).to all(include("after refreshing its cached selection"))
    end
  end
end
