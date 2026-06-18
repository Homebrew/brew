# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/ruby"

RSpec.describe Homebrew::DevCmd::Ruby do
  it_behaves_like "parseable arguments"

  it "executes ruby code with Homebrew's libraries loaded", :integration_test do
    expect { brew "ruby", "-e", "exit 0" }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  # Keep the richer expression path in-process as `brew ruby` subprocesses are slow.
  it "passes Homebrew libraries and code to Ruby" do
    cmd = described_class.new(["-e", "puts 'testball'.f.path"])

    expect(cmd).to receive(:exec).with(
      *HOMEBREW_RUBY_EXEC_ARGS,
      "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
      "-rglobal", "-rbrew_irb_helpers",
      "-e puts 'testball'.f.path"
    )

    cmd.run
  end
end
