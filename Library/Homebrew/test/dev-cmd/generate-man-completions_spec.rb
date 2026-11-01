# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-man-completions"

RSpec.describe Homebrew::DevCmd::GenerateManCompletions do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "generate-man-completions"

  it "reports an unchanged manpage and completions without an error" do
    command = described_class.new([])
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    allow(Commands).to receive(:rebuild_internal_commands_completion_list)
    allow(Homebrew::Manpages).to receive(:regenerate_man_pages)
    allow(Homebrew::Completions).to receive(:update_shell_completions!)
    allow(command).to receive(:system_command).and_return(
      instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: true)),
    )

    expect { command.run }
      .to output("No changes to manpage or completions.\n").to_stdout
      .and not_to_output.to_stderr
      .and change(Homebrew, :failed?).to(true)
  end
end
