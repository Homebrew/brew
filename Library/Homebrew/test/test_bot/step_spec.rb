# frozen_string_literal: true

require "test_bot"
require "ostruct"

RSpec.describe Homebrew::TestBot::Step do
  subject(:step) { described_class.new(command, env:, verbose:) }

  let(:command) { ["brew", "config"] }
  let(:env) { {} }
  let(:verbose) { false }

  describe "#run" do
    it "runs the command" do
      expect(step).to receive(:system_command)
        .with("brew", args: ["config"], env:, print_stderr: verbose, print_stdout: verbose)
        .and_return(instance_double(SystemCommand::Result, success?: true, merged_output: ""))
      step.run
    end
  end
end
