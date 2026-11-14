# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::Formula::FormulaStructGenerator do
  let(:raw_dependency_hash) do
    {
      "dependencies"           => [
        "foo",
        { "bar" => "build" },
        { "baz" => ["build", "test"] },
      ],
      "uses_from_macos"        => [
        "abc",
        { "def" => "build" },
        { "ghi" => ["build", "test"] },
        "jkl",
      ],
      "uses_from_macos_bounds" => [
        {},
        { "since" => "big_sur" },
        {},
        { "since" => "big_sur" },
      ],
    }
  end

  let(:symbolized_dependency_hash) do
    {
      "dependencies"           => [
        "foo",
        { "bar" => :build },
        { "baz" => [:build, :test] },
      ],
      "uses_from_macos"        => [
        "abc",
        { "def" => :build },
        { "ghi" => [:build, :test] },
        "jkl",
      ],
      "uses_from_macos_bounds" => [
        {},
        { since: :big_sur },
        {},
        { since: :big_sur },
      ],
    }
  end

  let(:dependency_args) do
    [
      "foo",
      { "bar" => :build },
      { "baz" => [:build, :test] },
    ]
  end

  let(:uses_from_macos_args) do
    [
      ["abc", {}],
      [{ "def" => :build, since: :big_sur }, {}],
      [{ "ghi" => [:build, :test] }, {}],
      ["jkl", { since: :big_sur }],
    ]
  end

  let(:requirements_array) do
    [
      { "name" => "linux", "specs" => ["head"] },
      { "name" => "codesign", "specs" => ["stable", "head"] },
      { "name" => "arch", "version" => "arm64", "specs" => ["stable", "head"] },
      { "name" => "macos", "version" => "14", "specs" => ["stable"] },
      { "name" => "maximum_macos", "version" => "13", "specs" => ["stable", "head"], "contexts" => ["build"] },
      { "name" => "xcode", "specs" => ["stable", "head"] },
      { "name" => "xcode", "version" => "11.2", "specs" => ["stable", "head"], "contexts" => ["build", "test"] },
    ]
  end

  let(:stable_requirements_args) do
    [
      { arch: [:arm64] },
      { macos: [:sonoma] },
      { maximum_macos: [:ventura, :build] },
      :xcode,
      { xcode: ["11.2", :build, :test] },
    ]
  end

  let(:head_requirements_args) do
    [
      :linux,
      { arch: [:arm64] },
      { maximum_macos: [:ventura, :build] },
      :xcode,
      { xcode: ["11.2", :build, :test] },
    ]
  end

  specify "::process_dependencies_and_requirements", :aggregate_failures do
    expect(
      described_class.process_dependencies_and_requirements(
        raw_dependency_hash, requirements_array, :stable
      ),
    ).to eq [dependency_args + stable_requirements_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(
        raw_dependency_hash, requirements_array, :head
      ),
    ).to eq [dependency_args + head_requirements_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(
        raw_dependency_hash, nil, :head
      ),
    ).to eq [dependency_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(
        nil, requirements_array, :stable
      ),
    ).to eq [stable_requirements_args, []]

    expect(
      described_class.process_dependencies_and_requirements(
        nil, requirements_array, :head
      ),
    ).to eq [head_requirements_args, []]

    expect(
      described_class.process_dependencies_and_requirements(
        nil, nil, :stable
      ),
    ).to eq [[], []]
  end

  it "annotates no_linkage dependencies without duplicating them" do
    deps_hash = {
      "dependencies"            => ["foo", "bar"],
      "test_dependencies"       => ["baz"],
      "no_linkage_dependencies" => ["bar", "baz"],
    }

    expect(described_class.process_dependencies_and_requirements(deps_hash, nil, :stable))
      .to eq [["foo", { "bar" => :no_linkage }, { "baz" => [:test, :no_linkage] }], []]
  end

  describe "::generate_formula_struct_hash" do
    subject(:struct) { described_class.generate_formula_struct_hash(hash) }

    let(:hash) do
      {
        "desc"                 => "Test formula",
        "homepage"             => "https://example.com",
        "license"              => "MIT",
        "ruby_source_checksum" => { "sha256" => "abc123" },
        "versions"             => { "stable" => "1.0.0" },
        "urls"                 => { "stable" => { "url" => "https://example.com/foo-1.0.tar.gz" } },
      }
    end

    it "carries each bottle's own manifest digest with its checksum" do
      hash["bottle"] = { "stable" => { "rebuild" => 0, "files" => {
        "arm64_sequoia" => { "cellar" => ":any", "sha256" => "checksum1", "manifest_sha256" => "manifest1" },
        "sequoia"       => { "cellar" => ":any", "sha256" => "checksum2" },
      } } }

      expect(struct.bottle_checksums).to eq([
        { cellar: :any, manifest_sha256: "manifest1", arm64_sequoia: "checksum1" },
        { cellar: :any, sequoia: "checksum2" },
      ])
    end

    it "falls back to stable deps when head_dependencies is absent" do
      hash.update({
        "dependencies"             => ["foo"],
        "recommended_dependencies" => [],
        "optional_dependencies"    => [],
        "uses_from_macos"          => [],
        "uses_from_macos_bounds"   => [],
      })
      expect(struct.head_dependencies).not_to be_empty
      expect(struct.head_dependencies).to eq struct.stable_dependencies
    end

    it "carries no_linkage dependencies into stable and head dependencies" do
      hash.update({
        "dependencies"            => ["foo", "bar"],
        "no_linkage_dependencies" => ["bar"],
      })
      expect([struct.stable_dependencies, struct.head_dependencies]).to all(eq(["foo", { "bar" => :no_linkage }]))
    end

    it "preserves stable patches" do
      hash.update({
        "patches" => [
          {
            "strip"  => "p1",
            "url"    => "https://example.com/foo.patch",
            "sha256" => "def456",
          },
        ],
      })
      expect(struct.stable_patches).to eq hash["patches"]
    end

    it "preserves local patch checksums through internal API serialisation" do
      hash["local_patch_checksums"] = { "Patches/foo.diff" => TEST_SHA256 }

      expect(struct.serialize["local_patch_checksums"])
        .to eq(hash["local_patch_checksums"])
    end

    context "when input contains placeholders" do
      let(:caveats_with_placeholder) { "Message about $HOMEBREW_CELLAR/foo/1.0.0/bin/foo" }
      let(:log_path_with_placeholder) { "$HOMEBREW_PREFIX/var/log/foo.log" }

      before do
        stub_const("HOMEBREW_PREFIX", "/tmp/homebrew")
        stub_const("HOMEBREW_CELLAR", "/tmp/homebrew/Cellar")
        hash.update({
          "caveats"      => caveats_with_placeholder,
          "service_args" => [[:log_path, log_path_with_placeholder]],
        })
      end

      it "replaces them when not generating JSON" do
        expect(struct.caveats).to eq "Message about /tmp/homebrew/Cellar/foo/1.0.0/bin/foo"
        expect(struct.service_args).to eq [[:log_path, "/tmp/homebrew/var/log/foo.log"]]
      end

      it "preserves them when generating JSON" do
        allow(Formula).to receive(:generating_hash?).and_return(true)
        expect(struct.caveats).to eq caveats_with_placeholder
        expect(struct.service_args).to eq [[:log_path, log_path_with_placeholder]]
      end
    end
  end

  specify "::symbolize_dependency_hash" do
    output = described_class.symbolize_dependency_hash(raw_dependency_hash)
    expect(output).to eq symbolized_dependency_hash
  end

  specify "::process_dependencies" do
    output = described_class.process_dependencies(symbolized_dependency_hash)
    expect(output).to eq dependency_args
  end

  describe "::process_dependencies" do
    it "combines build and test tags into one dependency" do
      expect(described_class.process_dependencies({
        "build_dependencies" => ["foo"],
        "test_dependencies"  => ["foo"],
      })).to eq [{ "foo" => [:build, :test] }]
    end

    it "appends no_linkage to combined dependency tags" do
      expect(described_class.process_dependencies({
        "build_dependencies"      => ["foo"],
        "test_dependencies"       => ["foo"],
        "no_linkage_dependencies" => ["foo"],
      })).to eq [{ "foo" => [:build, :test, :no_linkage] }]
    end

    it "preserves runtime dependencies alongside combined build and test tags" do
      expect(described_class.process_dependencies({
        "dependencies"       => ["foo"],
        "build_dependencies" => ["foo"],
        "test_dependencies"  => ["foo"],
      })).to eq ["foo", { "foo" => [:build, :test] }]
    end

    it "preserves no_linkage on runtime and tagged dependencies" do
      expect(described_class.process_dependencies({
        "dependencies"            => ["foo"],
        "test_dependencies"       => ["foo"],
        "no_linkage_dependencies" => ["foo"],
      })).to eq [{ "foo" => :no_linkage }, { "foo" => [:test, :no_linkage] }]
    end

    it "preserves recommended and no_linkage tags" do
      expect(described_class.process_dependencies({
        "recommended_dependencies" => ["foo"],
        "no_linkage_dependencies"  => ["foo"],
      })).to eq [{ "foo" => [:recommended, :no_linkage] }]
    end

    it "preserves first appearance and uses a fixed tag order" do
      expect(described_class.process_dependencies({
        "optional_dependencies"    => ["multi", "optional"],
        "recommended_dependencies" => ["multi", "recommended"],
        "test_dependencies"        => ["multi", "test"],
        "build_dependencies"       => ["build", "multi"],
        "dependencies"             => ["runtime"],
      })).to eq ["runtime", { "build" => :build }, { "multi" => [:build, :test, :recommended, :optional] },
                 { "test" => :test }, { "recommended" => :recommended }, { "optional" => :optional }]
    end
  end

  specify "::process_uses_from_macos" do
    output = described_class.process_uses_from_macos(symbolized_dependency_hash)
    expect(output).to eq uses_from_macos_args
  end
end
