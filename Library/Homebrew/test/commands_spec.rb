# frozen_string_literal: true

require "commands"

RSpec.shared_context "custom internal commands" do # rubocop:disable RSpec/ContextWording
  let(:cmds) do
    [
      # internal commands
      Commands::HOMEBREW_CMD_PATH/"rbcmd.rb",
      Commands::HOMEBREW_CMD_PATH/"shcmd.sh",

      # internal developer-commands
      Commands::HOMEBREW_DEV_CMD_PATH/"rbdevcmd.rb",
      Commands::HOMEBREW_DEV_CMD_PATH/"shdevcmd.sh",
    ]
  end

  around do |example|
    cmds.each do |f|
      FileUtils.touch f
    end

    example.run
  ensure
    FileUtils.rm_f cmds
  end
end

describe Commands do
  include_context "custom internal commands"

  specify "::internal_commands" do
    cmds = described_class.internal_commands
    expect(cmds).to include("rbcmd"), "Ruby commands files should be recognized"
    expect(cmds).to include("shcmd"), "Shell commands files should be recognized"
    expect(cmds).not_to include("rbdevcmd"), "Dev commands shouldn't be included"
  end

  specify "::internal_developer_commands" do
    cmds = described_class.internal_developer_commands
    expect(cmds).to include("rbdevcmd"), "Ruby commands files should be recognized"
    expect(cmds).to include("shdevcmd"), "Shell commands files should be recognized"
    expect(cmds).not_to include("rbcmd"), "Non-dev commands shouldn't be included"
  end

  specify "::external_commands" do
    mktmpdir do |dir|
      %w[t0.rb brew-t1 brew-t2.rb brew-t3.py].each do |file|
        path = "#{dir}/#{file}"
        FileUtils.touch path
        FileUtils.chmod 0755, path
      end

      FileUtils.touch "#{dir}/brew-t4"

      allow(Tap).to receive(:cmd_directories).and_return([dir])

      cmds = described_class.external_commands

      expect(cmds).to include("t0"), "Executable v2 Ruby files should be included"
      expect(cmds).to include("t1"), "Executable files should be included"
      expect(cmds).to include("t2"), "Executable Ruby files should be included"
      expect(cmds).to include("t3"), "Executable files with a Ruby extension should be included"
      expect(cmds).not_to include("t4"), "Non-executable files shouldn't be included"
    end
  end

  describe "::path" do
    specify "returns the path for an internal command" do
      expect(described_class.path("rbcmd")).to eq(HOMEBREW_LIBRARY_PATH/"cmd/rbcmd.rb")
      expect(described_class.path("shcmd")).to eq(HOMEBREW_LIBRARY_PATH/"cmd/shcmd.sh")
      expect(described_class.path("idontexist1234")).to be_nil
    end

    specify "returns the path for an internal developer-command" do
      expect(described_class.path("rbdevcmd")).to eq(HOMEBREW_LIBRARY_PATH/"dev-cmd/rbdevcmd.rb")
      expect(described_class.path("shdevcmd")).to eq(HOMEBREW_LIBRARY_PATH/"dev-cmd/shdevcmd.sh")
    end
  end
end
