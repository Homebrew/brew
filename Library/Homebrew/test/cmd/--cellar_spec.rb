# typed: strict
# frozen_string_literal: true

require "cmd/--cellar"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Cellar do
  it_behaves_like "parseable arguments"

  it "prints Homebrew's Cellar", :integration_test do
    expect { brew_sh "--cellar" }
      .to output("#{ENV.fetch("HOMEBREW_CELLAR")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints the Cellar for a Formula" do
    cmd = described_class.new(["testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae)
      .and_return([instance_double(Formula, rack: HOMEBREW_CELLAR/"testball")])

    expect { cmd.run }
      .to output(%r{#{HOMEBREW_CELLAR}/testball}o).to_stdout
      .and not_to_output.to_stderr
  end
end
