# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API do
  let(:text) { "foo" }
  let(:json) { '{"foo":"bar"}' }
  let(:json_hash) { JSON.parse(json) }
  let(:json_invalid) { '{"foo":"bar"' }

  before do
    described_class.clear_cache
  end

  def mock_curl_output(stdout: "", success: true)
    curl_output = instance_double(SystemCommand::Result, stdout:, success?: success)
    allow(Utils::Curl).to receive(:curl_output).and_return curl_output
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
  end

  describe "::fetch" do
    it "fetches a JSON file" do
      mock_curl_output stdout: json
      fetched_json = described_class.fetch("foo.json")
      expect(fetched_json).to eq json_hash
    end

    it "raises an error if the file does not exist" do
      mock_curl_output success: false
      expect { described_class.fetch("bar.txt") }.to raise_error(ArgumentError, /No file found/)
    end

    it "raises an error if the JSON file is invalid" do
      mock_curl_output stdout: text
      expect { described_class.fetch("baz.txt") }.to raise_error(ArgumentError, /Invalid JSON file/)
    end
  end

  describe "::fetch_json_api_file" do
    let!(:cache_dir) { mktmpdir }

    before do
      (cache_dir/"bar.json").write "tmp"
    end

    it "fetches a JSON file" do
      mock_curl_download stdout: json
      fetched_json, = described_class.fetch_json_api_file("foo.json", target: cache_dir/"foo.json")
      expect(fetched_json).to eq json_hash
    end

    it "updates an existing JSON file" do
      mock_curl_download stdout: json
      fetched_json, = described_class.fetch_json_api_file("bar.json", target: cache_dir/"bar.json")
      expect(fetched_json).to eq json_hash
    end

    it "raises an error if the JSON file is invalid" do
      mock_curl_download stdout: json_invalid
      expect do
        described_class.fetch_json_api_file("baz.json", target: cache_dir/"baz.json")
      end.to raise_error(SystemExit)
    end
  end

  describe "::tap_from_source_download" do
    let(:api_cache_root) { Homebrew::API::HOMEBREW_CACHE_API_SOURCE }
    let(:cache_path) do
      api_cache_root/"Homebrew"/"homebrew-core"/"cf5c386c1fa2cb54279d78c0990dd7a0fa4bc327"/"Formula"/"foo.rb"
    end

    context "when given a path inside the API source cache" do
      it "returns the corresponding tap" do
        expect(described_class.tap_from_source_download(cache_path)).to eq CoreTap.instance
      end
    end

    context "when given a path that is not inside the API source cache" do
      let(:api_cache_root) { mktmpdir }

      it "returns nil" do
        expect(described_class.tap_from_source_download(cache_path)).to be_nil
      end
    end

    context "when given a relative path that is not inside the API source cache" do
      it "returns nil" do
        expect(described_class.tap_from_source_download(Pathname("../foo.rb"))).to be_nil
      end
    end
  end
end
