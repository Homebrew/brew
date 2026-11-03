# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-maintainers"

RSpec.describe Homebrew::DevCmd::UpdateMaintainers do
  it_behaves_like "parseable arguments"

  it "updates the security team without removing members from the maintainer lists" do
    stub_const("HOMEBREW_REPOSITORY", mktmpdir)
    readme = HOMEBREW_REPOSITORY/"README.md"
    readme.write <<~MARKDOWN
      Homebrew's [Security Team](https://docs.brew.sh/Homebrew-Governance#4-security--emergency-actions) members are [Former member](https://github.com/former).
      Homebrew's [Lead Maintainers](https://docs.brew.sh/Homebrew-Governance#lead-maintainer) are Old lead.
      Homebrew's other Maintainers are Old maintainer.
    MARKDOWN
    command = described_class.new([])
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    allow(GitHub).to receive(:members_by_team).with("Homebrew", "lead-maintainers")
                                              .and_return({ "lead" => "Lead Maintainer" })
    allow(GitHub).to receive(:members_by_team).with("Homebrew", "maintainers")
                                              .and_return({ "lead"       => "Lead Maintainer",
                                                            "maintainer" => "Maintainer",
                                                            "security"   => "Security Member" })
    allow(GitHub).to receive(:members_by_team).with("Homebrew", "security")
                                              .and_return({ "security" => "Security Member",
                                                            "lead"     => "Lead Maintainer" })
    allow(command).to receive(:system_command).and_return(
      instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: false)),
    )
    allow(command).to receive(:puts)
    allow(Homebrew::Manpages).to receive(:regenerate_man_pages)

    command.run

    expect(readme.read).to eq(<<~MARKDOWN)
      Homebrew's [Security Team](https://docs.brew.sh/Homebrew-Governance#4-security--emergency-actions) members are [Lead Maintainer](https://github.com/lead) and [Security Member](https://github.com/security).
      Homebrew's [Lead Maintainers](https://docs.brew.sh/Homebrew-Governance#lead-maintainer) are [Lead Maintainer](https://github.com/lead).
      Homebrew's other Maintainers are [Maintainer](https://github.com/maintainer) and [Security Member](https://github.com/security).
    MARKDOWN
  end

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
