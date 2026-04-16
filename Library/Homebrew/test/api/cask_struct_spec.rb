# typed: false
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::CaskStruct do
  describe "::from_hash" do
    it "constructs a valid struct from a hash with all field types" do
      hash = {
        "sha256"               => "abc123",
        "version"              => "1.0.0",
        "ruby_source_checksum" => { sha256: "def456" },
        "names"                => ["Test Cask"],
        "desc"                 => "A test cask",
        "homepage"             => "https://example.com",
        "auto_updates"         => true,
        "languages"            => ["en"],
        "url_args"             => ["https://example.com/file.dmg"],
        "url_kwargs"           => { verified: "example.com/" },
        "conflicts_with_args"  => { cask: ["other-cask"] },
        "depends_on_args"      => { macos: ">= :catalina" },
        "container_args"       => { type: :zip },
        "deprecate_args"       => { date: "2025-01-01", because: :discontinued },
        "raw_artifacts"        => [[:app, ["Test.app"], {}, nil]],
        "raw_caveats"          => "Requires restart.",
      }

      struct = described_class.from_hash(hash)

      expect(struct.sha256).to eq("abc123")
      expect(struct.version).to eq("1.0.0")
      expect(struct.names).to eq(["Test Cask"])
      expect(struct.desc).to eq("A test cask")
      expect(struct.homepage).to eq("https://example.com")
      expect(struct.auto_updates).to be(true)
      expect(struct.languages).to eq(["en"])
    end

    it "ignores unknown/extra keys" do
      hash = {
        "sha256"               => "abc123",
        "version"              => "1.0.0",
        "ruby_source_checksum" => { sha256: "def456" },
        "totally_unknown_key"  => "should be ignored",
        "another_unknown"      => 42,
      }

      expect { described_class.from_hash(hash) }.not_to raise_error
    end
  end

  describe "predicate methods" do
    it "defaults all predicates to false for a minimal struct" do
      struct = described_class.new(
        sha256:               "abc123",
        version:              "1.0.0",
        ruby_source_checksum: { sha256: "def456" },
      )

      Homebrew::API::CaskStruct::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be(false),
                                                 "expected #{predicate}? to default to false"
      end
    end

    it "returns true when the corresponding _present field is set" do
      present_fields = Homebrew::API::CaskStruct::PREDICATES.to_h do |predicate|
        [:"#{predicate}_present", true]
      end

      struct = described_class.new(
        sha256:               "abc123",
        version:              "1.0.0",
        ruby_source_checksum: { sha256: "def456" },
        **present_fields,
      )

      Homebrew::API::CaskStruct::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be(true),
                                                 "expected #{predicate}? to be true"
      end
    end
  end

  describe "#artifacts" do
    it "replaces placeholders in artifact arguments" do
      struct = described_class.new(
        sha256:               "abc123",
        version:              "1.0.0",
        ruby_source_checksum: { sha256: "def456" },
        raw_artifacts:        [[:app, ["#{HOMEBREW_CASK_APPDIR_PLACEHOLDER}/Test.app"], {}, nil]],
      )

      result = struct.artifacts(appdir: "/Applications")

      expect(result).to eq([[:app, ["/Applications/Test.app"], {}, nil]])
    end
  end

  describe "#caveats" do
    it "replaces placeholders in caveats string" do
      struct = described_class.new(
        sha256:               "abc123",
        version:              "1.0.0",
        ruby_source_checksum: { sha256: "def456" },
        raw_caveats:          "Installed to #{HOMEBREW_PREFIX_PLACEHOLDER}/bin",
      )

      result = struct.caveats(appdir: "/Applications")

      expect(result).to eq("Installed to #{HOMEBREW_PREFIX}/bin")
    end

    it "returns nil when raw_caveats is nil" do
      struct = described_class.new(
        sha256:               "abc123",
        version:              "1.0.0",
        ruby_source_checksum: { sha256: "def456" },
      )

      expect(struct.caveats(appdir: "/Applications")).to be_nil
    end
  end

  specify "#serialize_artifact_args", :aggregate_failures do
    struct = described_class.new(
      sha256:               "abc123",
      version:              "1.0.0",
      ruby_source_checksum: { sha256: "def456" },
    )

    expect(struct.serialize_artifact_args([:preflight, [], {}, -> {}]))
      .to eq([:preflight, [], {}, :empty_block])

    expect(struct.serialize_artifact_args([:preflight, ["foo"], { bar: "baz" }, nil]))
      .to eq([:preflight, ["foo"], { bar: "baz" }, nil])
  end

  specify "::deserialize_artifact_args", :aggregate_failures do
    expect(described_class.deserialize_artifact_args([:foo]))
      .to eq([:foo, [], {}, nil])

    expect(described_class.deserialize_artifact_args([:foo, ["abc", "def"]]))
      .to eq([:foo, ["abc", "def"], {}, nil])

    expect(described_class.deserialize_artifact_args([:foo, { ghi: "jkl" }]))
      .to eq([:foo, [], { ghi: "jkl" }, nil])

    expect(described_class.deserialize_artifact_args([:foo, :empty_block]))
      .to eq([:foo, [], {}, described_class::EMPTY_BLOCK])

    expect(described_class.deserialize_artifact_args([:foo, ["abc", "def"], { ghi: "jkl" }]))
      .to eq([:foo, ["abc", "def"], { ghi: "jkl" }, nil])

    expect(described_class.deserialize_artifact_args([:foo, ["abc", "def"], :empty_block]))
      .to eq([:foo, ["abc", "def"], {}, described_class::EMPTY_BLOCK])

    expect(described_class.deserialize_artifact_args([:foo, { ghi: "jkl" }, :empty_block]))
      .to eq([:foo, [], { ghi: "jkl" }, described_class::EMPTY_BLOCK])

    expect(described_class.deserialize_artifact_args([:foo, ["abc", "def"], { ghi: "jkl" }, :empty_block]))
      .to eq([:foo, ["abc", "def"], { ghi: "jkl" }, described_class::EMPTY_BLOCK])
  end

  describe "::deserialize" do
    it "populates predicate fields to false when not specified" do
      hash = {
        "sha256"               => "abc123",
        "version"              => "1.0.0",
        "ruby_source_checksum" => { sha256: "def456" },
      }

      struct = described_class.deserialize(hash)

      described_class::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be false
      end
    end

    it "populates special predicate fields", :aggregate_failures do
      hash = {
        "auto_updates"         => true,
        "raw_caveats"          => "Some caveats",
        "conflicts_with_args"  => { cask: ["other-cask"] },
        "container_args"       => { type: :zip },
        "depends_on_args"      => { macos: ">= :catalina" },
        "deprecate_args"       => { date: "2025-01-01", because: :unmaintained },
        "desc"                 => "A description",
        "disable_args"         => { date: "2025-01-01", because: :unmaintained },
        "homepage"             => "https://example.com",
        "sha256"               => "abc123",
        "version"              => "1.0.0",
        "ruby_source_checksum" => { sha256: "def456" },
      }

      struct = described_class.deserialize(hash)

      described_class::PREDICATES.each do |predicate|
        expect(struct.send(:"#{predicate}?")).to be true
      end
    end
  end

  describe "serialize/deserialize round-trip" do
    it "reconstructs an equivalent struct after serialize then deserialize", :needs_macos do
      original = described_class.new(
        auto_updates:         true,
        auto_updates_present: true,
        caveats_present:      true,
        conflicts_present:    true,
        conflicts_with_args:  { cask: ["other-cask"] },
        container_args:       { type: :zip },
        container_present:    true,
        depends_on_args:      { macos: ">= :catalina" },
        depends_on_present:   true,
        deprecate_args:       { date: "2025-01-01", because: :unmaintained },
        deprecate_present:    true,
        desc:                 "A description",
        desc_present:         true,
        disable_args:         { date: "2025-01-01", because: :unmaintained },
        disable_present:      true,
        homepage:             "https://example.com",
        homepage_present:     true,
        languages:            ["en"],
        names:                ["Test Cask"],
        raw_artifacts:        [[:app, ["#{HOMEBREW_CASK_APPDIR_PLACEHOLDER}/Test.app"], {}, nil]],
        raw_caveats:          "Some caveats",
        renames:              [["Old Name", "New Name"]],
        ruby_source_checksum: { sha256: "def456" },
        ruby_source_path:     "/path/to/source",
        sha256:               "abc123",
        tap_string:           "homebrew/cask",
        url_args:             ["https://example.com/file.dmg"],
        url_kwargs:           { verified: "example.com/" },
        version:              "1.0.0",
      )

      serialized = original.serialize
      restored = described_class.deserialize(serialized)

      expect(restored).to eq(original)
    end
  end
end
