# typed: strict
# frozen_string_literal: true

require "utils/repology"

RSpec.describe Repology do
  before do
    allow(Utils::Curl).to receive(:curl_supports_tls13?).and_return(true)
    allow(Homebrew::EnvConfig).to receive(:developer?).and_return(false)
  end

  describe ".single_package_query" do
    sig {
      params(success: T::Boolean, stdout: String, stderr: String, exit_status: Integer)
        .returns(T.untyped)
    }
    def stub_curl(success:, stdout: "", stderr: "", exit_status: 0)
      instance_double(SystemCommand::Result, success?: success, stdout:, stderr:, exit_status:)
    end

    it "URL-encodes the project name and passes --fail" do
      expect(Utils::Curl).to receive(:curl_output) do |*args, **|
        expect(args).to include("--fail", "#{Repology::API_BASE}/project/gtk%2B3")
        stub_curl(success: true, stdout: "[]")
      end
      expect(described_class.single_package_query("gtk+3", repository: Repology::HOMEBREW_CORE))
        .to eq({ "gtk+3" => [] })
    end

    it "returns nil (rather than raising) on HTTP failure" do
      allow(Utils::Curl).to receive(:curl_output).and_return(
        stub_curl(success: false, exit_status: 22, stderr: "The requested URL returned error: 503"),
      )
      expect(described_class.single_package_query("curl", repository: Repology::HOMEBREW_CORE))
        .to be_nil
    end

    it "returns nil on invalid JSON" do
      allow(Utils::Curl).to receive(:curl_output).and_return(stub_curl(success: true, stdout: "not json"))
      expect(described_class.single_package_query("curl", repository: Repology::HOMEBREW_CORE))
        .to be_nil
    end
  end

  describe ".query_api" do
    it "URL-encodes the pagination cursor" do
      expect(Utils::Curl).to receive(:curl_output) do |*args, **|
        expect(args.last).to eq "#{Repology::API_BASE}/projects/gtk%2B3/" \
                                "?inrepo=#{Repology::HOMEBREW_CORE}&outdated=1"
        instance_double(SystemCommand::Result, stdout: "{}")
      end
      described_class.query_api("gtk+3", repository: Repology::HOMEBREW_CORE)
    end
  end
end
