# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-bottle-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateBottleCiMatrix do
  it_behaves_like "parseable arguments"

  it "checks runners against their bottle tags" do
    runners = {
      "15"                  => Utils::Bottles::Tag.from_symbol(:x86_64_sequoia),
      "15.4-arm64"          => Utils::Bottles::Tag.from_symbol(:arm64_sequoia),
      "ubuntu-latest"       => Utils::Bottles.tag(:x86_64_linux),
      "ubuntu-24.04-arm"    => Utils::Bottles.tag(:arm64_linux),
      "linux-arm64"         => Utils::Bottles.tag(:arm64_linux),
      "linux-x86_64"        => Utils::Bottles.tag(:x86_64_linux),
      "linux-self-hosted-1" => Utils::Bottles.tag(:x86_64_linux),
    }
    command = described_class.new(["--runners=#{runners.keys.join(",")}", "testball"])
    bottle_specification = instance_double(BottleSpecification)
    formula = instance_double(Formula, name: "testball", bottle_specification:)
    tag_checks = []
    allow(command.args.named).to receive(:to_formulae).and_return([formula])
    allow(command).to receive(:puts)
    allow(bottle_specification).to receive(:tag?) do |tag, no_older_versions:|
      tag_checks << [tag, no_older_versions]
      false
    end
    ENV["GITHUB_RUN_ID"] = "123"
    ENV.delete("GITHUB_OUTPUT")

    command.run

    expect(tag_checks).to eq(runners.values.map { |tag| [tag, true] })
  end

  it "fails for an existing Linux ARM bottle" do
    command = described_class.new(["--runners=linux-arm64", "testball"])
    bottle_specification = instance_double(BottleSpecification, tag?: true)
    formula = instance_double(Formula, name: "testball", bottle_specification:)
    allow(command.args.named).to receive(:to_formulae).and_return([formula])
    ENV["GITHUB_RUN_ID"] = "123"
    ENV.delete("GITHUB_OUTPUT")

    expect { command.run }
      .to change(Homebrew, :failed?).from(false).to(true)
      .and output(/testball already has a bottle for arm64_linux/).to_stderr
  end

  it "generates the dispatched bottle runner matrix", :integration_test do
    setup_test_formula "testball"

    mktmpdir do |path|
      github_output = path/"github-output"
      runners = "15-arm64,ubuntu-24.04-arm,linux-arm64,linux-x86_64,custom-runner"

      expect do
        expect do
          brew "generate-bottle-ci-matrix", "--runners=#{runners}", "testball",
               "GITHUB_OUTPUT" => github_output.to_s,
               "GITHUB_RUN_ID" => "123"
        end.to be_a_success
      end.to output(/"runner": "linux-arm64-123-dispatch"/).to_stdout

      expect(JSON.parse(github_output.read.delete_prefix("runners="))).to eq(
        [
          { "runner" => "15-arm64-123-dispatch", "cleanup" => false },
          {
            "runner"    => "ubuntu-24.04-arm",
            "container" => {
              "image"   => "ghcr.io/homebrew/brew:main",
              "options" => "--user=linuxbrew",
            },
            "workdir"   => "/github/home",
            "cleanup"   => false,
          },
          { "runner" => "linux-arm64-123-dispatch", "cleanup" => false },
          { "runner" => "linux-x86_64-123-dispatch", "cleanup" => false },
          { "runner" => "custom-runner", "cleanup" => true },
        ],
      )
    end
  end
end
