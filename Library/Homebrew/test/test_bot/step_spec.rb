# typed: true
# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::Step do
  subject(:step) { described_class.new(command, env:, verbose:) }

  let(:command) { ["brew", "config"] }
  let(:env) { {} }
  let(:verbose) { false }

  describe "#run" do
    test_each([RuntimeError.new("cask installation failed"), SystemExit.new(1)]) do |error|
      it "records an in-process #{error.class} before exiting with --fail-fast" do
        expect { step.run(fail_fast: true) { raise error } }
          .to raise_error(SystemExit).and change { [step.status, step.output] }.to([:failed, error.message])
      end
    end

    it "runs the command" do
      expect(step).to receive(:system_command)
        .with("brew", args: ["config"], env:, print_stderr: verbose, print_stdout: verbose)
        .and_return(instance_double(SystemCommand::Result, success?: true, merged_output: ""))
      step.run
    end
  end
end
