# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/verify"

RSpec.describe Homebrew::DevCmd::Verify do
  it_behaves_like "parseable arguments"

  it "reports missing attestations as verification failures" do
    command = described_class.new(["fakebottle"])
    formula = instance_double(Formula)
    bottle = instance_double(Bottle, fetch: nil, filename: "fakebottle--1.0.faketag.bottle.tar.gz")
    bottle_tag = instance_double(Utils::Bottles::Tag)
    named_args = instance_double(Homebrew::CLI::NamedArgs, to_formulae: [formula])
    args = double(deps?: false, named: named_args, os_arch_combinations: [[nil, nil]], bottle_tag: nil,
                  force?: false, json?: false)

    allow(command).to receive(:args).and_return(args)
    allow(Homebrew::SimulateSystem).to receive(:with).and_yield
    allow(Utils::Bottles::Tag).to receive(:from_arg).and_return(bottle_tag)
    allow(formula).to receive(:bottle_for_tag).with(bottle_tag).and_return(bottle)
    allow(Homebrew::Attestation).to receive(:check_core_attestation)
      .with(bottle)
      .and_raise(Homebrew::Attestation::MissingAttestationError, "attestation not found")

    expect(command).to receive(:ofail)
      .with(include("Failed to verify fakebottle--1.0.faketag.bottle.tar.gz", "attestation not found"))

    command.run
  end
end
