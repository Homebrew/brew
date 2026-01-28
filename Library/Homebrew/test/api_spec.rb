# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API do
  let(:text) { "foo" }
  let(:json) { '{"foo":"bar"}' }
  let(:json_hash) { JSON.parse(json) }
  let(:json_invalid) { '{"foo":"bar"' }

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

  describe "::merge_variations" do
    let(:arm64_sequoia_tag) { Utils::Bottles::Tag.new(system: :sequoia, arch: :arm) }
    let(:sonoma_tag) { Utils::Bottles::Tag.new(system: :sonoma, arch: :intel) }
    let(:x86_64_linux_tag) { Utils::Bottles::Tag.new(system: :linux, arch: :intel) }

    let(:json) do
      {
        "name"       => "foo",
        "foo"        => "bar",
        "baz"        => ["test1", "test2"],
        "variations" => {
          "arm64_sequoia" => { "foo" => "new" },
          :sonoma         => { "baz" => ["new1", "new2", "new3"] },
        },
      }
    end

    let(:arm64_sequoia_result) do
      {
        "name" => "foo",
        "foo"  => "new",
        "baz"  => ["test1", "test2"],
      }
    end

    let(:sonoma_result) do
      {
        "name" => "foo",
        "foo"  => "bar",
        "baz"  => ["new1", "new2", "new3"],
      }
    end

    it "returns the original JSON if no variations are found" do
      result = described_class.merge_variations(arm64_sequoia_result, bottle_tag: arm64_sequoia_tag)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the original JSON if no variations are found for the current system" do
      result = described_class.merge_variations(arm64_sequoia_result)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the original JSON without the variations if no matching variation is found" do
      result = described_class.merge_variations(json, bottle_tag: x86_64_linux_tag)
      expect(result).to eq json.except("variations")
    end

    it "returns the original JSON without the variations if no matching variation is found for the current system" do
      Homebrew::SimulateSystem.with(os: :linux, arch: :intel) do
        result = described_class.merge_variations(json)
        expect(result).to eq json.except("variations")
      end
    end

    it "returns the JSON with the matching variation applied from a string key" do
      result = described_class.merge_variations(json, bottle_tag: arm64_sequoia_tag)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the JSON with the matching variation applied from a string key for the current system" do
      Homebrew::SimulateSystem.with(os: :sequoia, arch: :arm) do
        result = described_class.merge_variations(json)
        expect(result).to eq arm64_sequoia_result
      end
    end

    it "returns the JSON with the matching variation applied from a symbol key" do
      result = described_class.merge_variations(json, bottle_tag: sonoma_tag)
      expect(result).to eq sonoma_result
    end

    it "returns the JSON with the matching variation applied from a symbol key for the current system" do
      Homebrew::SimulateSystem.with(os: :sonoma, arch: :intel) do
        result = described_class.merge_variations(json)
        expect(result).to eq sonoma_result
      end
    end
  end
end
