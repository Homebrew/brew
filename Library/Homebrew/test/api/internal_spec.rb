# typed: true
# frozen_string_literal: true

require "api/internal"

RSpec.describe Homebrew::API::Internal do
  let(:cache_dir) { mktmpdir }
  let(:packages_json) do
    <<~JSON
      {
        "formulae": {
          "foo": {
            "desc": "Foo formula",
            "executables": ["foo-bin", "food"],
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
        "casks": {
          "foo": {
            "desc": "Foo cask",
            "homepage": "https://example.com/foo",
            "sha256": "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38",
            "version": "1.0.0"
          },
          "bar": {
            "desc": "Bar cask",
            "homepage": "https://example.com/bar",
            "sha256": "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a",
            "version": "0.4.0"
          },
          "baz": {
            "desc": "Baz cask",
            "homepage": "https://example.com/baz",
            "sha256": "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7",
            "version": "10.4.5"
          }
        },
        "formula_aliases": {
          "foo-alias1": "foo",
          "foo-alias2": "foo",
          "bar-alias": "bar"
        },
        "formula_renames": {
          "foo-old": "foo",
          "bar-old": "bar",
          "baz-old": "baz"
        },
        "cask_renames": {
          "foo-old": "foo",
          "bar-old": "bar",
          "baz-old": "baz"
        },
        "formula_tap_git_head": "b871900717ccbb3508ca93fa56e128940b9bd371",
        "cask_tap_git_head": "030eea17b14b437b0a7b96f4dbc9473cce4be31c",
        "formula_tap_migrations": {
          "abc": "some/tap",
          "def": "another/tap"
        },
        "cask_tap_migrations": {
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
        "executables"          => ["foo-bin", "food"],
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
  let(:cask_hashes) do
    {
      "foo" => {
        "desc"     => "Foo cask",
        "homepage" => "https://example.com/foo",
        "sha256"   => "09f88b61e36045188ddb1b1ba8e402b9f3debee1770cc4ca91355eeccb5f4a38",
        "version"  => "1.0.0",
      },
      "bar" => {
        "desc"     => "Bar cask",
        "homepage" => "https://example.com/bar",
        "sha256"   => "bb6e3408f39a404770529cfce548dc2666e861077acd173825cb3138c27c205a",
        "version"  => "0.4.0",
      },
      "baz" => {
        "desc"     => "Baz cask",
        "homepage" => "https://example.com/baz",
        "sha256"   => "404c97537d65ca0b75c389e7d439dcefb9b56f34d3b98017669eda0d0501add7",
        "version"  => "10.4.5",
      },
    }
  end
  let(:formula_structs) do
    formula_hashes.to_h do |name, hash|
      struct = Homebrew::API::FormulaStruct.new(**hash.transform_keys(&:to_sym))
      [name, struct]
    end
  end
  let(:cask_structs) do
    cask_hashes.to_h do |name, hash|
      struct = Homebrew::API::CaskStruct.new(**hash.transform_keys(&:to_sym))
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
  let(:cask_renames) do
    {
      "foo-old" => "foo",
      "bar-old" => "bar",
      "baz-old" => "baz",
    }
  end
  let(:formula_tap_git_head) { "b871900717ccbb3508ca93fa56e128940b9bd371" }
  let(:cask_tap_git_head) { "030eea17b14b437b0a7b96f4dbc9473cce4be31c" }
  let(:formula_tap_migrations) do
    {
      "abc" => "some/tap",
      "def" => "another/tap",
    }
  end
  let(:cask_tap_migrations) do
    {
      "abc" => "some/tap",
      "def" => "another/tap",
    }
  end

  before do
    FileUtils.mkdir_p(cache_dir/"internal")
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
    described_class.clear_cache
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write packages_json
    end
    allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
      [true, json_data]
    end
  end

  it "returns the expected formula structs" do
    formula_structs.each do |name, struct|
      expect(described_class.formula_struct(name)).to eq struct
    end
  end

  it "returns the expected cask structs" do
    cask_structs.each do |name, struct|
      expect(described_class.cask_struct(name)).to eq struct
    end
  end

  it "returns the expected formula hashes" do
    formula_hashes_output = described_class.formula_hashes
    expect(formula_hashes_output).to eq formula_hashes
  end

  it "writes formula executables from the internal packages JSON" do
    Homebrew::API.write_names_and_aliases

    expect((cache_dir/"internal/executables.txt").read).to eq("foo:foo-bin food\n")
  end

  it "writes formula aliases and renames as cached mappings" do
    Homebrew::API.write_names_and_aliases

    mappings = formulae_aliases.merge(formulae_renames).map { |old_name, name| "#{old_name}|#{name}" }.sort
    expect((cache_dir/"formula_aliases.txt").read.lines(chomp: true)).to eq(
      mappings,
    )
  end

  it "returns the expected cask hashes" do
    cask_hashes_output = described_class.cask_hashes
    expect(cask_hashes_output).to eq cask_hashes
  end

  it "returns the expected formula alias list" do
    formula_aliases_output = described_class.formula_aliases
    expect(formula_aliases_output).to eq formulae_aliases
  end

  it "returns the expected formula rename list" do
    formula_renames_output = described_class.formula_renames
    expect(formula_renames_output).to eq formulae_renames
  end

  it "returns the expected cask rename list" do
    cask_renames_output = described_class.cask_renames
    expect(cask_renames_output).to eq cask_renames
  end

  it "returns the expected formula tap git head" do
    formula_tap_git_head_output = described_class.formula_tap_git_head
    expect(formula_tap_git_head_output).to eq formula_tap_git_head
  end

  it "returns the expected cask tap git head" do
    cask_tap_git_head_output = described_class.cask_tap_git_head
    expect(cask_tap_git_head_output).to eq cask_tap_git_head
  end

  it "returns the expected formula tap migrations list" do
    formula_tap_migrations_output = described_class.formula_tap_migrations
    expect(formula_tap_migrations_output).to eq formula_tap_migrations
  end

  it "returns the expected cask tap migrations list" do
    cask_tap_migrations_output = described_class.cask_tap_migrations
    expect(cask_tap_migrations_output).to eq cask_tap_migrations
  end

  describe "with a cached payload sidecar" do
    let(:compact_payload) { JSON.generate(JSON.parse(packages_json)) }

    before do
      target = described_class.cached_packages_json_file_path
      target.dirname.mkpath
      target.write "envelope"
      header = {
        "protected"       => "protected",
        "signature"       => "signature",
        "source_size"     => target.stat.size,
        "source_mtime_ns" => (target.stat.mtime.to_r * 1_000_000_000).to_i,
      }
      Pathname("#{target}.payload").write("#{JSON.generate(header)}\n#{compact_payload}")
      allow(Homebrew::API).to receive(:verify_jws_signature).and_return(nil)
      allow(Utils::Curl).to receive(:curl_download).and_raise("sidecar-served loads must not download")
    end

    it "builds an index on first load and serves formula structs from it afterwards" do
      expect(described_class.formula_struct("foo")).to eq formula_structs.fetch("foo")
      index_path = Homebrew::API::PackagesIndex.path_for(described_class.cached_packages_json_file_path)
      expect(index_path).to exist

      described_class.clear_cache
      loaded_index = T.let(nil, T.untyped)
      expect(Homebrew::API::PackagesIndex).to receive(:load).and_wrap_original do |original, *args, **kwargs|
        loaded_index = original.call(*args, **kwargs)
      end

      expect(described_class.formula_struct("foo")).to eq formula_structs.fetch("foo")
      expect(loaded_index).not_to be_nil
      expect(described_class.formula_tap_git_head).to eq formula_tap_git_head
      expect(described_class.formula_name?("bar")).to be true
      expect(described_class.formula_name?("missing")).to be false
    end

    it "materialises full hashes from an index-served payload" do
      described_class.formula_struct("foo")
      described_class.clear_cache

      expect(described_class.formula_hashes).to eq formula_hashes
    end
  end
end
