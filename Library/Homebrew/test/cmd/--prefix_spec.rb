# typed: strict
# frozen_string_literal: true

require "cmd/--prefix"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Prefix do
  it_behaves_like "parseable arguments"

  it "prints Homebrew's prefix", :integration_test do
    expect { brew_sh "--prefix" }
      .to output("#{ENV.fetch("HOMEBREW_PREFIX")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints the prefix for a Formula" do
    cmd = described_class.new(["testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae)
      .and_return([instance_double(Formula, opt_prefix: HOMEBREW_PREFIX/"opt/testball")])

    expect { cmd.run }
      .to output("#{HOMEBREW_PREFIX}/opt/testball\n").to_stdout
      .and not_to_output.to_stderr
  end

  it "errors if the given Formula doesn't exist" do
    cmd = described_class.new(["nonexistent"])
    allow(cmd.args.named).to receive(:to_resolved_formulae)
      .and_raise(FormulaUnavailableError.new("nonexistent"))

    expect { cmd.run }.to raise_error(FormulaUnavailableError, /nonexistent/)
  end

  it "prints a warning when `--installed` is used and the given Formula is not installed" do
    cmd = described_class.new(["--installed", "testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([
      instance_double(Formula, name: "testball", opt_prefix: HOMEBREW_PREFIX/"opt/testball", optlinked?: false),
    ])

    expect { cmd.run }
      .to raise_error(NotAKegError, /testball/)
  end
end
