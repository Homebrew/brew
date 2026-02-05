# frozen_string_literal: true

require "commands"

# These shared contexts starting with `when` don't make sense.
RSpec.shared_context "custom internal commands" do # rubocop:disable RSpec/ContextWording
  let(:tmpdir) { mktmpdir }
  let(:cmd_path) { tmpdir/"cmd" }
  let(:dev_cmd_path) { tmpdir/"dev-cmd" }
  let(:cmds) do
    [
      # internal commands
      cmd_path/"rbcmd.rb",
      cmd_path/"shcmd.sh",

      # internal developer-commands
      dev_cmd_path/"rbdevcmd.rb",
      dev_cmd_path/"shdevcmd.sh",
    ]
  end

  before do
    stub_const("Commands::HOMEBREW_CMD_PATH", cmd_path)
    stub_const("Commands::HOMEBREW_DEV_CMD_PATH", dev_cmd_path)
  end

  around do |example|
    cmd_path.mkpath
    dev_cmd_path.mkpath
    cmds.each do |f|
      FileUtils.touch f
    end

    example.run
  ensure
    FileUtils.rm_f cmds
  end
end

RSpec.describe Commands do
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

      allow(described_class).to receive(:tap_cmd_directories).and_return([dir])

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
      expect(described_class.path("rbcmd")).to eq(Commands::HOMEBREW_CMD_PATH/"rbcmd.rb")
      expect(described_class.path("shcmd")).to eq(Commands::HOMEBREW_CMD_PATH/"shcmd.sh")
      expect(described_class.path("idontexist1234")).to be_nil
    end

    specify "returns the path for an internal developer-command" do
      expect(described_class.path("rbdevcmd")).to eq(Commands::HOMEBREW_DEV_CMD_PATH/"rbdevcmd.rb")
      expect(described_class.path("shdevcmd")).to eq(Commands::HOMEBREW_DEV_CMD_PATH/"shdevcmd.sh")
    end
  end
end
