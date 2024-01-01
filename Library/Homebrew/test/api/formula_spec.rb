# frozen_string_literal: true

require "api"

describe Homebrew::API::Formula do
  let(:cache_dir) { mktmpdir }

  before do
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
    described_class.clear_cache
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
    allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
      [true, json_data]
    end
  end

  describe "::all_formulae" do
    let(:formulae_json) do
      <<~EOS
        [{
          "name": "foo",
          "url": "https://brew.sh/foo",
          "aliases": ["foo-alias1", "foo-alias2"]
        }, {
          "name": "bar",
          "url": "https://brew.sh/bar",
          "aliases": ["bar-alias"]
        }, {
          "name": "baz",
          "url": "https://brew.sh/baz",
          "aliases": []
        }]
      EOS
    end
    let(:formulae_hash) do
      {
        "foo" => { "url" => "https://brew.sh/foo", "aliases" => ["foo-alias1", "foo-alias2"] },
        "bar" => { "url" => "https://brew.sh/bar", "aliases" => ["bar-alias"] },
        "baz" => { "url" => "https://brew.sh/baz", "aliases" => [] },
      }
    end
    let(:formulae_aliases) do
      {
        "foo-alias1" => "foo",
        "foo-alias2" => "foo",
        "bar-alias"  => "bar",
      }
    end

    it "returns the expected formula JSON list" do
      mock_curl_download stdout: formulae_json
      formulae_output = described_class.all_formulae
      expect(formulae_output).to eq formulae_hash
    end

    it "returns the expected formula alias list" do
      mock_curl_download stdout: formulae_json
      aliases_output = described_class.all_aliases
      expect(aliases_output).to eq formulae_aliases
    end
  end
end
