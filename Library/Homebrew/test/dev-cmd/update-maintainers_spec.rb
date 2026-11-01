# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-maintainers"

RSpec.describe Homebrew::DevCmd::UpdateMaintainers do
  it_behaves_like "parseable arguments"

  it "reports an unchanged list of maintainers without an error" do
    stub_const("HOMEBREW_REPOSITORY", mktmpdir)
    (HOMEBREW_REPOSITORY/"README.md").write ""
    command = described_class.new([])
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    allow(GitHub).to receive(:members_by_team).and_return({})
    allow(command).to receive(:system_command).and_return(
      instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: true)),
    )

    expect { command.run }
      .to output("No changes to list of maintainers.\n").to_stdout
      .and not_to_output.to_stderr
      .and change(Homebrew, :failed?).to(true)
  end
end
