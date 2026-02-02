# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::FormulaStruct do
  describe "#serialize_bottle" do
    def build_formula_struct(checksums)
      Homebrew::API::FormulaStruct.new(
        desc:                 "sample formula",
        homepage:             "https://example.com",
        license:              "MIT",
        ruby_source_checksum: "abc123",
        stable_version:       "1.0.0",
        bottle_checksums:     checksums,
      )
    end

    specify :aggregate_failures, :needs_macos do
      struct = build_formula_struct([
        { cellar: :any, arm64_sequoia: "checksum1" },
        { cellar: :any_skip_relocation, sequoia: "checksum2" },
        { cellar: "/opt/homebrew/Cellar", arm64_sonoma: "checksum3" },
      ])

      arm64_tahoe = Utils::Bottles::Tag.from_symbol(:arm64_tahoe)
      arm64_sequoia = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      sequoia = Utils::Bottles::Tag.from_symbol(:sequoia)
      arm64_sonoma = Utils::Bottles::Tag.from_symbol(:arm64_sonoma)
      x86_64_linux = Utils::Bottles::Tag.from_symbol(:x86_64_linux)

      expect(struct.serialize_bottle(bottle_tag: arm64_tahoe)).to eq(
        {
          "bottle_tag"      => :arm64_sequoia,
          "bottle_cellar"   => :any,
          "bottle_checksum" => "checksum1",
        },
      )

      expect(struct.serialize_bottle(bottle_tag: arm64_sequoia)).to eq(
        {
          "bottle_tag"      => nil,
          "bottle_cellar"   => :any,
          "bottle_checksum" => "checksum1",
        },
      )

      expect(struct.serialize_bottle(bottle_tag: sequoia)).to eq(
        {
          "bottle_tag"      => nil,
          "bottle_cellar"   => nil,
          "bottle_checksum" => "checksum2",
        },
      )

      expect(struct.serialize_bottle(bottle_tag: arm64_sonoma)).to eq(
        {
          "bottle_tag"      => nil,
          "bottle_cellar"   => "/opt/homebrew/Cellar",
          "bottle_checksum" => "checksum3",
        },
      )

      expect(struct.serialize_bottle(bottle_tag: x86_64_linux)).to be_nil
    end

    it "serializes bottle with all tag" do
      all_struct = build_formula_struct([{ cellar: :any_skip_relocation, all: "checksum1" }])
      all_struct_result = {
        "bottle_tag"      => :all,
        "bottle_cellar"   => nil,
        "bottle_checksum" => "checksum1",
      }

      [:arm64_tahoe, :sequoia, :x86_64_linux].each do |tag_sym|
        bottle_tag = Utils::Bottles::Tag.from_symbol(tag_sym)
        expect(all_struct.serialize_bottle(bottle_tag: bottle_tag)).to eq(all_struct_result)
      end
    end
  end

  describe "::format_arg_pair" do
    specify(:aggregate_failures) do
      expect(described_class.format_arg_pair(["foo"], last: {})).to eq ["foo", {}]
      expect(described_class.format_arg_pair([{ "foo" => :build }], last: {}))
        .to eq [{ "foo" => :build }, {}]
      expect(described_class.format_arg_pair([{ "foo" => :build, since: :catalina }], last: {}))
        .to eq [{ "foo" => :build, since: :catalina }, {}]
      expect(described_class.format_arg_pair(["foo", { since: :catalina }], last: {}))
        .to eq ["foo", { since: :catalina }]

      expect(described_class.format_arg_pair([:foo], last: nil)).to eq [:foo, nil]
      expect(described_class.format_arg_pair([:foo, :bar], last: nil)).to eq [:foo, :bar]
    end
  end
end
