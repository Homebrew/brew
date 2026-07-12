# typed: strict
# frozen_string_literal: true

require "cmd/postinstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Postinstall do
  it_behaves_like "parseable arguments"

  it "runs post-install steps before the remaining `post_install` hook" do
    cmd = described_class.new(["foo"])
    formula = instance_double(Formula, install_etc_var: nil, post_install_steps_defined?: true,
                                       post_install_defined?: true, to_s: "foo")
    installer = instance_double(FormulaInstaller)

    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([formula])
    expect(formula).to receive(:run_post_install_steps).ordered
    expect(FormulaInstaller).to receive(:new)
      .with(formula, debug: false, quiet: false, verbose: false)
      .ordered
      .and_return(installer)
    expect(installer).to receive(:post_install).ordered

    cmd.run
  end
end
