# typed: false
# frozen_string_literal: true

require "utils/shell_completion"

RSpec.describe Utils::ShellCompletion do
  describe ".default_completion_shells" do
    it "returns bash, zsh, and fish for nil format" do
      expect(described_class.default_completion_shells(nil)).to eq([:bash, :zsh, :fish])
    end

    it "returns bash, zsh, and fish for unrecognized format" do
      expect(described_class.default_completion_shells(:unknown)).to eq([:bash, :zsh, :fish])
    end

    it "includes pwsh for cobra format" do
      expect(described_class.default_completion_shells(:cobra)).to eq([:bash, :zsh, :fish, :pwsh])
    end

    it "includes pwsh for typer format" do
      expect(described_class.default_completion_shells(:typer)).to eq([:bash, :zsh, :fish, :pwsh])
    end
  end

  describe ".completion_shell_parameter" do
    let(:env) { {} }

    it "returns shell name for nil format" do
      expect(described_class.completion_shell_parameter(nil, :bash, "/usr/bin/foo", env)).to eq("bash")
    end

    it "returns --shell=<name> for :arg format" do
      expect(described_class.completion_shell_parameter(:arg, :zsh, "/usr/bin/foo", env)).to eq("--shell=zsh")
    end

    it "sets env and returns nil for :clap format" do
      result = described_class.completion_shell_parameter(:clap, :fish, "/usr/bin/foo", env)
      expect(result).to be_nil
      expect(env["COMPLETE"]).to eq("fish")
    end

    it "sets env with uppercased program name for :click format" do
      result = described_class.completion_shell_parameter(:click, :bash, "/usr/local/bin/my-tool", env)
      expect(result).to be_nil
      expect(env["_MY_TOOL_COMPLETE"]).to eq("bash_source")
    end

    it "returns subcommand array for :cobra format" do
      result = described_class.completion_shell_parameter(:cobra, :zsh, "/usr/bin/foo", env)
      expect(result).to eq(["completion", "zsh"])
    end

    it "returns --<shell> for :flag format" do
      expect(described_class.completion_shell_parameter(:flag, :fish, "/usr/bin/foo", env)).to eq("--fish")
    end

    it "returns nil for :none format" do
      expect(described_class.completion_shell_parameter(:none, :bash, "/usr/bin/foo", env)).to be_nil
    end

    it "returns subcommand array for :typer format and sets env" do
      result = described_class.completion_shell_parameter(:typer, :bash, "/usr/bin/foo", env)
      expect(result).to eq(["--show-completion", "bash"])
      expect(env["_TYPER_COMPLETE_TEST_DISABLE_SHELL_DETECTION"]).to eq("1")
    end

    it "maps :pwsh to 'powershell'" do
      expect(described_class.completion_shell_parameter(nil, :pwsh, "/usr/bin/foo", env)).to eq("powershell")
    end

    it "interpolates custom format string" do
      expect(described_class.completion_shell_parameter("--complete-", :zsh, "/usr/bin/foo", env))
        .to eq("--complete-zsh")
    end
  end

  describe ".generate_completion_output" do
    it "calls safe_popen_read with commands and shell parameter" do
      expect(Utils).to receive(:safe_popen_read).with(
        {}, "/usr/bin/foo", "completions", "bash", err: :err
      ).and_return("completion output")

      result = described_class.generate_completion_output(
        ["/usr/bin/foo", "completions"], "bash", {}
      )

      expect(result).to eq("completion output")
    end

    it "flattens array shell parameters" do
      expect(Utils).to receive(:safe_popen_read).with(
        {}, "/usr/bin/foo", "completion", "zsh", err: :err
      ).and_return("output")

      described_class.generate_completion_output(
        ["/usr/bin/foo"], ["completion", "zsh"], {}
      )
    end

    it "handles nil shell parameter" do
      expect(Utils).to receive(:safe_popen_read).with(
        {}, "/usr/bin/foo", err: :err
      ).and_return("output")

      described_class.generate_completion_output(["/usr/bin/foo"], nil, {})
    end
  end
end
