# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/verify"

RSpec.describe Homebrew::DevCmd::Verify do
  subject(:command) { described_class.new(["thirdparty/tap/fformula-name"]) }

  it_behaves_like "parseable arguments"

  it "checks whether a Formula has a bottle to verify", :integration_test do
    setup_test_formula "testball"

    expect { brew "verify", "testball" }
      .to output(/Bottle for tag .* is unavailable\./).to_stderr
      .and be_a_success
  end

  describe "#run" do
    let(:named_args) { instance_double(Homebrew::CLI::NamedArgs) }
    let(:formula) do
      tap = Tap.fetch("thirdparty", "tap")
      path = Formulary.find_formula_in_tap("fformula-name", tap)
      Class.new(Formula) do
        url "https://brew.sh/fformula-name-1.0.tar.gz"
      end.new("fformula-name", path, :stable, tap:)
    end
    let(:bottle) do
      instance_double(
        Bottle,
        clear_cache: nil,
        fetch:       nil,
        filename:    "fformula-name--1.0.#{Homebrew::SimulateSystem.current_arch}.bottle.tar.gz",
      )
    end
    let(:os_arch_combinations) do
      [[Homebrew::SimulateSystem.current_os, Homebrew::SimulateSystem.current_arch]]
    end
    let(:args) do
      object_double(
        command.args,
        deps?:                false,
        named:                named_args,
        os_arch_combinations:,
        bottle_tag:           nil,
        force?:               false,
        json?:                false,
      )
    end

    before do
      allow(command).to receive(:args).and_return(args)
      allow(named_args).to receive(:to_formulae).and_return([formula])
      allow(formula).to receive(:bottle_for_tag).and_return(bottle)
      allow(Homebrew).to receive(:failed=)
    end

    it "verifies bottles from supported third-party taps" do
      expect(Homebrew::Attestation).to receive(:check_formula_attestation)
        .with(bottle)
        .and_return({})

      expect { command.run }
        .to output(/has a valid attestation/).to_stdout
    end

    it "prints only JSON to stdout with `--json`" do
      allow(args).to receive(:json?).and_return(true)
      expect(Homebrew::Attestation).to receive(:check_formula_attestation)
        .with(bottle)
        .and_return({})

      expect { command.run }
        .to output("[{}]\n").to_stdout
    end

    it "marks the command as failed for unsupported taps" do
      expect(Homebrew::Attestation).to receive(:check_formula_attestation)
        .with(bottle)
        .and_raise(Homebrew::Attestation::UnsupportedTapError, "tap cannot be attested safely")
      expect(Homebrew).to receive(:failed=).with(true)

      expect { command.run }
        .to output(/tap cannot be attested safely/).to_stderr
    end
  end
end
