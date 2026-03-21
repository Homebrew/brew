# frozen_string_literal: true

require "download_strategy"

RSpec.describe GitHubPrivateReleaseAssetDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version) }

  let(:name) { "myapp" }
  let(:version) { nil }
  let(:url) { "https://github.com/owner/myapp/releases/download/v1.2.3/myapp-linux-amd64.tar.gz" }
  let(:ghe_url) { "https://github.example.com/owner/myapp/releases/download/v1.2.3/myapp-linux-amd64.tar.gz" }
  let(:ghe_port_url) { "https://github.example.com:8443/owner/myapp/releases/download/v1.2.3/myapp-linux-amd64.tar.gz" }
  let(:encoded_url) { "https://github.com/owner/myapp/releases/download/v1.2.3/myapp%20linux%20amd64.tar.gz" }

  it "parses the URL and sets the corresponding instance variables" do
    expect(strategy.instance_variable_get(:@owner)).to eq("owner")
    expect(strategy.instance_variable_get(:@repo)).to eq("myapp")
    expect(strategy.instance_variable_get(:@tag)).to eq("v1.2.3")
    expect(strategy.instance_variable_get(:@filename)).to eq("myapp-linux-amd64.tar.gz")
    expect(strategy.instance_variable_get(:@github_server_url)).to eq("https://github.com")
  end

  it "URL-decodes percent-encoded filenames" do
    strategy = described_class.new(encoded_url, name, version)
    expect(strategy.instance_variable_get(:@filename)).to eq("myapp linux amd64.tar.gz")
  end

  context "with an enterprise server URL" do
    subject(:strategy) { described_class.new(ghe_url, name, version) }

    it "auto-detects the server URL from the URL" do
      expect(strategy.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
      expect(strategy.instance_variable_get(:@owner)).to eq("owner")
      expect(strategy.instance_variable_get(:@repo)).to eq("myapp")
      expect(strategy.instance_variable_get(:@tag)).to eq("v1.2.3")
      expect(strategy.instance_variable_get(:@filename)).to eq("myapp-linux-amd64.tar.gz")
    end

    it "uses an explicitly provided github_server_url" do
      explicit = described_class.new(ghe_url, name, version, github_server_url: "https://github.example.com")
      expect(explicit.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
    end

    it "strips trailing slashes from the provided github_server_url" do
      trailing = described_class.new(ghe_url, name, version, github_server_url: "https://github.example.com///")
      expect(trailing.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
    end

    it "preserves a non-default port when auto-detecting the server URL" do
      strategy = described_class.new(ghe_port_url, name, version)
      expect(strategy.instance_variable_get(:@github_server_url)).to eq("https://github.example.com:8443")
    end
  end

  context "when the URL does not match the expected pattern" do
    subject(:strategy) { described_class.new("https://example.com/download/v1/file.tar.gz", name, version) }

    it "leaves owner, repo, tag, and filename as nil" do
      expect(strategy.instance_variable_get(:@owner)).to be_nil
      expect(strategy.instance_variable_get(:@repo)).to be_nil
      expect(strategy.instance_variable_get(:@tag)).to be_nil
      expect(strategy.instance_variable_get(:@filename)).to be_nil
    end
  end
end
