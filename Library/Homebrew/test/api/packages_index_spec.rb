# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::PackagesIndex do
  let(:cache_dir) { mktmpdir }
  let(:target) { cache_dir/"packages.arm64_test.jws.json" }
  let(:parsed) do
    {
      "formulae"             => {
        "foo" => { "desc" => "Foo formula", "stable_version" => "1.0.0" },
        "bar" => { "desc" => "Bar‑formula", "stable_version" => "0.4.0" },
      },
      "casks"                => {
        "foo" => { "desc" => "Foo cask", "version" => "2.0.0" },
      },
      "formula_aliases"      => { "foo-alias" => "foo" },
      "formula_tap_git_head" => "b871900717ccbb3508ca93fa56e128940b9bd371",
    }
  end
  let(:payload) { JSON.generate(parsed) }

  def write_index!
    target.write("{}")
    described_class.write!(target, payload:, parsed:, source_stat: target.stat)
  end

  def load_index
    described_class.load(target, payload:, source_stat: target.stat)
  end

  it "serves entries and top-level values from a written index" do
    write_index!
    index = load_index

    expect(index).not_to be_nil
    expect(index.formula_hash("foo")).to eq parsed.dig("formulae", "foo")
    expect(index.formula_hash("bar")).to eq parsed.dig("formulae", "bar")
    expect(index.cask_hash("foo")).to eq parsed.dig("casks", "foo")
    expect(index.formula_hash("missing")).to be_nil
    expect(index.formula_names).to eq %w[foo bar]
    expect(index.cask_name?("foo")).to be true
    expect(index.top_level_value("formula_aliases")).to eq parsed["formula_aliases"]
    expect(index.top_level_value("formula_tap_git_head")).to eq parsed["formula_tap_git_head"]
    expect(index.top_level_value("formulae")).to be_nil
  end

  it "does not load an index whose source envelope changed" do
    write_index!
    FileUtils.touch target, mtime: target.stat.mtime + 1

    expect(load_index).to be_nil
  end

  it "does not load an index built for a different payload" do
    write_index!

    expect(described_class.load(target, payload: "#{payload} ", source_stat: target.stat)).to be_nil
  end

  it "raises on lookups whose recorded offsets do not match the payload" do
    write_index!
    index_path = described_class.path_for(target)
    data = JSON.parse(index_path.read)
    data["formulae"]["foo"] = data["formulae"]["bar"]
    index_path.write(JSON.generate(data))

    expect { load_index.formula_hash("foo") }.to raise_error(Homebrew::API::PackagesIndex::Invalid)
  end

  it "raises on lookups remapped to a matching key in another section" do
    write_index!
    index_path = described_class.path_for(target)
    data = JSON.parse(index_path.read)
    data["formulae"]["foo"] = data["casks"]["foo"]
    index_path.write(JSON.generate(data))

    expect { load_index.formula_hash("foo") }.to raise_error(Homebrew::API::PackagesIndex::Invalid)
  end

  it "does not load an index whose top-level spans do not tile the payload" do
    write_index!
    index_path = described_class.path_for(target)
    data = JSON.parse(index_path.read)
    data["top_level"]["formulae"][1] = data["payload_bytesize"] - data["top_level"]["formulae"][0] - 1
    index_path.write(JSON.generate(data))

    expect(load_index).to be_nil
  end
end
