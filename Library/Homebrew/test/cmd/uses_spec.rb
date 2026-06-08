# typed: true
# frozen_string_literal: true

require "cli/named_args"
require "cmd/shared_examples/args_parse"
require "cmd/uses"
require "fileutils"

RSpec.describe Homebrew::Cmd::Uses do
  include FileUtils

  it_behaves_like "parseable arguments"

  it "uses tap trust configuration to evaluate all formulae" do
    used_formula = instance_double(Formula, full_name: "foo")
    cmd = described_class.new(["--formula", "foo"])

    allow(cmd.args.named).to receive(:to_formulae).and_return([used_formula])
    expect(Formula).to receive(:all).with(eval_all: true).and_return([])

    expect { with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") { cmd.run } }
      .to not_to_output.to_stderr
  end

  it "handles unavailable formula" do
    cmd = described_class.new(%w[foo --include-optional --recursive])
    allow(cmd.args.named)
      .to receive(:to_formulae)
      .and_raise(FormulaUnavailableError, "foo")
    allow(cmd).to receive(:intersection_of_dependents)
      .and_return([
        instance_double(Formula, full_name: "bar"),
        instance_double(Formula, full_name: "optional"),
      ])

    allow(Homebrew::Trust).to receive(:trusted?).and_return(true)

    expect { cmd.run }
      .to output(/^(bar\noptional|optional\nbar)$/).to_stdout
      .and output(/Error: Missing formulae should not have dependents!\n/).to_stderr
      .and raise_error SystemExit
  end
end
