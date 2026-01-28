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
            "foo": ["1.0.0", 0, 0, "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38"],
            "bar": ["0.4.0_5", 1, 0, "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a"],
            "baz": ["10.4.5_2", 0, 2, "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7"]
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
          "tap_migrations": {
            "abc": "some/tap",
            "def": "another/tap"
          }
        }
      JSON
    end
    let(:formula_arrays) do
      {
        "foo" => ["1.0.0", 0, 0, "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38"],
        "bar" => ["0.4.0_5", 1, 0, "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a"],
        "baz" => ["10.4.5_2", 0, 2, "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7"],
      }
    end
    let(:formula_stubs) do
      formula_arrays.to_h do |name, (pkg_version, version_scheme, rebuild, sha256)|
        stub = Homebrew::FormulaStub.new(
          name:           name,
          pkg_version:    PkgVersion.parse(pkg_version),
          version_scheme: version_scheme,
          rebuild:        rebuild,
          sha256:         sha256,
          aliases:        formulae_aliases.select { |_, new_name| new_name == name }.keys,
          oldnames:       formulae_renames.select { |_, new_name| new_name == name }.keys,
        )
        [name, stub]
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
    let(:formula_tap_migrations) do
      {
        "abc" => "some/tap",
        "def" => "another/tap",
      }
    end

    it "returns the expected formula stubs" do
      mock_curl_download stdout: formula_json
      formula_stubs.each do |name, stub|
        expect(described_class.formula_stub(name)).to eq stub
      end
    end

    it "returns the expected formula arrays" do
      mock_curl_download stdout: formula_json
      formula_arrays_output = described_class.formula_arrays
      expect(formula_arrays_output).to eq formula_arrays
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
