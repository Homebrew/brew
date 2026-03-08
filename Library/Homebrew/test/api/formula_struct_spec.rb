# typed: true
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

  describe "predicate methods" do
    it "defaults all predicates to false when not set" do
      struct = described_class.new(
        desc:                 "test",
        homepage:             "https://example.com",
        license:              "MIT",
        ruby_source_checksum: "abc123",
        stable_version:       "1.0.0",
      )

      Homebrew::API::FormulaStruct::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be(false),
                                                 "expected #{predicate}? to default to false"
      end
    end

    it "returns true when the corresponding _present field is set" do
      present_fields = Homebrew::API::FormulaStruct::PREDICATES.to_h do |predicate|
        [:"#{predicate}_present", true]
      end

      struct = described_class.new(
        desc:                 "test",
        homepage:             "https://example.com",
        license:              "MIT",
        ruby_source_checksum: "abc123",
        stable_version:       "1.0.0",
        **present_fields,
      )

      Homebrew::API::FormulaStruct::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be(true),
                                                 "expected #{predicate}? to be true"
      end
    end
  end

  describe "::deserialize" do
    it "reconstructs a struct from a serialized hash with bottle info" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
        "bottle_checksum"      => "checksum1",
        "bottle_tag"           => ":arm64_sequoia",
        "bottle_cellar"        => ":any",
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.bottle?).to be(true)
      expect(struct.bottle_checksums).to eq([{ cellar: :any, arm64_sequoia: "checksum1" }])
    end

    it "sets bottle_present to false when no bottle_checksum is present" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.bottle?).to be(false)
      expect(struct.bottle_checksums).to eq([])
    end

    it "sets predicate _present fields from _args presence" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
        "deprecate_args"       => { ":date" => "2025-01-01", ":because" => "discontinued" },
        "keg_only_args"        => [":versioned_formula"],
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.deprecate?).to be(true)
      expect(struct.keg_only?).to be(true)
      expect(struct.disable?).to be(false)
    end

    it "formats _url_args into [String, Hash] pairs" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
        "stable_url_args"      => ["https://example.com/foo-1.0.tar.gz"],
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.stable?).to be(true)
      expect(struct.stable_url_args).to eq(["https://example.com/foo-1.0.tar.gz", {}])
    end

    it "formats uses_from_macos into arg pairs" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                   => "test formula",
        "homepage"               => "https://example.com",
        "license"                => "MIT",
        "ruby_source_checksum"   => "abc123",
        "stable_version"         => "1.0.0",
        "stable_url_args"        => ["https://example.com/foo-1.0.tar.gz"],
        "stable_uses_from_macos" => [["zlib"]],
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.stable_uses_from_macos).to eq([["zlib", {}]])
    end

    it "formats service_args into arg pairs" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
        "service_args"         => [[":run_type", ":immediate"]],
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.service?).to be(true)
      expect(struct.service_args).to eq([[:run_type, :immediate]])
    end

    it "formats conflicts into arg pairs" do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)
      hash = {
        "desc"                 => "test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => "abc123",
        "stable_version"       => "1.0.0",
        "conflicts"            => [["other-formula"]],
      }

      struct = described_class.deserialize(hash, bottle_tag:)

      expect(struct.conflicts).to eq([["other-formula", {}]])
    end
  end

  describe "serialize/deserialize round-trip" do
    it "reconstructs an equivalent struct after serialize then deserialize", :needs_macos do
      bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sequoia)

      original = described_class.new(
        desc:                   "round-trip test",
        homepage:               "https://example.com",
        license:                "MIT",
        ruby_source_checksum:   "abc123",
        stable_version:         "1.0.0",
        stable_present:         true,
        stable_url_args:        ["https://example.com/foo-1.0.tar.gz", {}],
        stable_dependencies:    ["dep1", { "dep2" => :build }],
        stable_uses_from_macos: [["zlib", {}]],
        bottle_present:         true,
        bottle_checksums:       [{ cellar: :any, arm64_sequoia: "checksum1" }],
        conflicts:              [["other-formula", {}]],
        revision:               2,
        aliases:                ["foo-alias"],
        post_install_defined:   true,
      )

      serialized = original.serialize(bottle_tag:)
      restored = described_class.deserialize(serialized, bottle_tag:)

      expect(restored).to eq(original)
    end
  end
end
