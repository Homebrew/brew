# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::Analytics do
  let(:cache_dir) { mktmpdir }

  before do
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
    described_class.clear_cache
  end

  def mock_curl_output(stdout, success: true)
    allow(Utils::Curl).to receive(:curl_output)
      .and_return(instance_double(SystemCommand::Result, success?: success, stdout:))
  end

  def mock_curl_download(stdout)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].dirname.mkpath
      kwargs[:to].write stdout
    end
  end

  describe "::fetch" do
    it "fetches an analytics listing" do
      mock_curl_output '{"items":[]}'

      expect(described_class.fetch("install", 30)).to eq("items" => [])
    end

    it "raises an error if the file does not exist" do
      mock_curl_output "", success: false

      expect { described_class.fetch("install", 30) }.to raise_error(ArgumentError, /No file found/)
    end

    it "raises an error if the JSON file is invalid" do
      mock_curl_output "foo"

      expect { described_class.fetch("install", 30) }.to raise_error(ArgumentError, /Invalid JSON file/)
    end

    it "raises an error if the JSON file is not an object" do
      mock_curl_output "[]"

      expect { described_class.fetch("install", 30) }.to raise_error(ArgumentError, /Invalid JSON file/)
    end
  end

  describe "::formula_analytics" do
    it "keeps only the analytics data from the unsigned per-formula response" do
      mock_curl_download <<~JSON
        {
          "name": "wget",
          "urls": { "stable": { "url": "https://example.com/wget.tar.gz" } },
          "post_install_steps": ["rm -rf /"],
          "analytics": { "install": { "30d": { "wget": 10 } } }
        }
      JSON

      expect(described_class.formula_analytics("wget")).to eq("install" => { "30d" => { "wget" => 10 } })
    end

    it "returns nil when the response has no analytics hash" do
      mock_curl_download '{"name":"wget","analytics":[]}'

      expect(described_class.formula_analytics("wget")).to be_nil
    end

    it "revalidates a stale cached response" do
      target = cache_dir/"formula/wget.json"
      target.dirname.mkpath
      target.write('{"analytics":{"install":{"30d":{"wget":1}}}}')
      FileUtils.touch(target, mtime: Time.now - (2 * 60 * 60))
      mock_curl_download '{"analytics":{"install":{"30d":{"wget":2}}}}'

      expect(described_class.formula_analytics("wget")).to eq("install" => { "30d" => { "wget" => 2 } })
    end

    it "reuses a fresh cached response without downloading" do
      target = cache_dir/"formula/wget.json"
      target.dirname.mkpath
      target.write('{"analytics":{"install":{"30d":{"wget":1}}}}')
      expect(Utils::Curl).not_to receive(:curl_download)

      expect(described_class.formula_analytics("wget")).to eq("install" => { "30d" => { "wget" => 1 } })
    end
  end

  describe "::cask_analytics" do
    it "keeps only the analytics data from the unsigned per-cask response" do
      mock_curl_download <<~JSON
        {
          "token": "firefox",
          "artifacts": [{ "app": ["Firefox.app"] }],
          "analytics": { "install": { "30d": { "firefox": 5 } } }
        }
      JSON

      expect(described_class.cask_analytics("firefox")).to eq("install" => { "30d" => { "firefox" => 5 } })
    end
  end
end
