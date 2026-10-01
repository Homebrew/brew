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

  specify "::process_uses_from_macos" do
    output = described_class.process_uses_from_macos(symbolized_dependency_hash)
    expect(output).to eq uses_from_macos_args
  end
end
