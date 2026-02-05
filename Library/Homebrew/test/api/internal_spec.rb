# frozen_string_literal: true

require "api/internal"

RSpec.describe Homebrew::API::Internal do
  let(:cache_dir) { mktmpdir }

  before do
    FileUtils.mkdir_p(cache_dir/"internal")
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
    allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
      [true, json_data]
    end
  end

  context "for formulae" do
    let(:formula_json) do
      <<~JSON
        {
          "formulae": {
            "foo": {
              "desc": "Foo formula",
              "homepage": "https://example.com/foo",
              "license": "MIT",
              "ruby_source_checksum": "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38",
              "stable_version": "1.0.0"
            },
            "bar": {
              "desc": "Bar formula",
              "homepage": "https://example.com/bar",
              "license": "Apache-2.0",
              "ruby_source_checksum": "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a",
              "stable_version": "0.4.0",
              "revision": 5,
              "version_scheme": 1
            },
            "baz": {
              "desc": "Baz formula",
              "homepage": "https://example.com/baz",
              "license": "GPL-3.0-or-later",
              "ruby_source_checksum": "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7",
              "stable_version": "10.4.5",
              "revision": 2,
              "bottle_rebuild": 2
            }
          },
          "aliases": {
            "foo-alias1": "foo",
            "foo-alias2": "foo",
            "bar-alias": "bar"
          },
          "renames": {
            "foo-old": "foo",
            "bar-old": "bar",
            "baz-old": "baz"
          },
          "tap_git_head": "b871900717ccbb3508ca93fa56e128940b9bd371",
          "tap_migrations": {
            "abc": "some/tap",
            "def": "another/tap"
          }
        }
      JSON
    end
    let(:formula_hashes) do
      {
        "foo" => {
          "desc"                 => "Foo formula",
          "homepage"             => "https://example.com/foo",
          "license"              => "MIT",
          "ruby_source_checksum" => "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38",
          "stable_version"       => "1.0.0",
        },
        "bar" => {
          "desc"                 => "Bar formula",
          "homepage"             => "https://example.com/bar",
          "license"              => "Apache-2.0",
          "ruby_source_checksum" => "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a",
          "stable_version"       => "0.4.0",
          "revision"             => 5,
          "version_scheme"       => 1,
        },
        "baz" => {
          "desc"                 => "Baz formula",
          "homepage"             => "https://example.com/baz",
          "license"              => "GPL-3.0-or-later",
          "ruby_source_checksum" => "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7",
          "stable_version"       => "10.4.5",
          "revision"             => 2,
          "bottle_rebuild"       => 2,
        },
      }
    end
    let(:formula_structs) do
      formula_hashes.to_h do |name, hash|
        struct = Homebrew::API::FormulaStruct.new(**hash.transform_keys(&:to_sym))
        [name, struct]
      end
    end
    let(:formulae_aliases) do
      {
        "foo-alias1" => "foo",
        "foo-alias2" => "foo",
        "bar-alias"  => "bar",
      }
    end
    let(:formulae_renames) do
      {
        "foo-old" => "foo",
        "bar-old" => "bar",
        "baz-old" => "baz",
      }
    end
    let(:formula_tap_git_head) { "b871900717ccbb3508ca93fa56e128940b9bd371" }
    let(:formula_tap_migrations) do
      {
        "abc" => "some/tap",
        "def" => "another/tap",
      }
    end

    it "returns the expected formula structs" do
      mock_curl_download stdout: formula_json
      formula_structs.each do |name, struct|
        expect(described_class.formula_struct(name)).to eq struct
      end
    end

    it "returns the expected formula hashes" do
      mock_curl_download stdout: formula_json
      formula_hashes_output = described_class.formula_hashes
      expect(formula_hashes_output).to eq formula_hashes
    end

    it "returns the expected formula alias list" do
      mock_curl_download stdout: formula_json
      formula_aliases_output = described_class.formula_aliases
      expect(formula_aliases_output).to eq formulae_aliases
    end

    it "returns the expected formula rename list" do
      mock_curl_download stdout: formula_json
      formula_renames_output = described_class.formula_renames
      expect(formula_renames_output).to eq formulae_renames
    end

    it "returns the expected formula tap git head" do
      mock_curl_download stdout: formula_json
      formula_tap_git_head_output = described_class.formula_tap_git_head
      expect(formula_tap_git_head_output).to eq formula_tap_git_head
    end

    it "returns the expected formula tap migrations list" do
      mock_curl_download stdout: formula_json
      formula_tap_migrations_output = described_class.formula_tap_migrations
      expect(formula_tap_migrations_output).to eq formula_tap_migrations
    end
  end

  context "for casks" do
    let(:cask_json) do
      <<~JSON
        {
          "casks": {
            "foo": { "version": "1.0.0" },
            "bar": { "version": "0.4.0" },
            "baz": { "version": "10.4.5" }
          },
          "renames": {
            "foo-old": "foo",
            "bar-old": "bar",
            "baz-old": "baz"
          },
          "tap_migrations": {
            "abc": "some/tap",
            "def": "another/tap"
          }
        }
      JSON
    end
    let(:cask_hashes) do
      {
        "foo" => { "version" => "1.0.0" },
        "bar" => { "version" => "0.4.0" },
        "baz" => { "version" => "10.4.5" },
      }
    end
    let(:cask_renames) do
      {
        "foo-old" => "foo",
        "bar-old" => "bar",
        "baz-old" => "baz",
      }
    end
    let(:cask_tap_migrations) do
      {
        "abc" => "some/tap",
        "def" => "another/tap",
      }
    end

    it "returns the expected cask hashes" do
      mock_curl_download stdout: cask_json
      cask_hashes_output = described_class.cask_hashes
      expect(cask_hashes_output).to eq cask_hashes
    end

    it "returns the expected cask rename list" do
      mock_curl_download stdout: cask_json
      cask_renames_output = described_class.cask_renames
      expect(cask_renames_output).to eq cask_renames
    end

    it "returns the expected cask tap migrations list" do
      mock_curl_download stdout: cask_json
      cask_tap_migrations_output = described_class.cask_tap_migrations
      expect(cask_tap_migrations_output).to eq cask_tap_migrations
    end
  end
end
