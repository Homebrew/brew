# typed: true
# frozen_string_literal: true

require "cmd/sandbox-exec"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::SandboxExec do
  it_behaves_like "parseable arguments"

  it "runs the command in the requested sandbox" do
    expect(Sandbox).to receive(:run_command)
      .with("make", "test", writable_path: ".", deny_network: true)

    described_class.new(["--deny-network", ".", "--", "make", "test"]).run
  end
end
