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
        { "since" => "catalina" },
        {},
        { "since" => "catalina" },
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
        { since: :catalina },
        {},
        { since: :catalina },
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
      [{ "def" => :build, since: :catalina }, {}],
      [{ "ghi" => [:build, :test] }, {}],
      ["jkl", { since: :catalina }],
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
      described_class.process_dependencies_and_requirements(raw_dependency_hash, requirements_array, :stable),
    ).to eq [dependency_args + stable_requirements_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(raw_dependency_hash, requirements_array, :head),
    ).to eq [dependency_args + head_requirements_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(raw_dependency_hash, nil, :head),
    ).to eq [dependency_args, uses_from_macos_args]

    expect(
      described_class.process_dependencies_and_requirements(nil, requirements_array, :stable),
    ).to eq [stable_requirements_args, []]

    expect(
      described_class.process_dependencies_and_requirements(nil, requirements_array, :head),
    ).to eq [head_requirements_args, []]

    expect(
      described_class.process_dependencies_and_requirements(nil, nil, :stable),
    ).to eq [[], []]
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
