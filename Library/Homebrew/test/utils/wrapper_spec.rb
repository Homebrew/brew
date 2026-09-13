# typed: strict
# frozen_string_literal: true

RSpec.describe "brew wrapper", type: :system do
  sig { returns(SystemCommand::Result) }
  subject(:result) { SystemCommand.run(HOMEBREW_BREW_FILE, args: ["commands", "--quiet"]) }

  before do
    ENV["HOMEBREW_FORCE_BREW_WRAPPER"] = "/wrapper/brew"
    ENV["HOMEBREW_BREW_WRAPPER"] = "/wrapper/brew"
    ENV.delete("HOMEBREW_NO_FORCE_BREW_WRAPPER")
    ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
    ENV.delete("HOMEBREW_FORCE_BREW_WRAPPER_HELP_MESSAGE")
    ENV.delete("HOMEBREW_DEVELOPER")
    ENV["HOMEBREW_COLOR"] = ""
  end

  it "warns about obsolete wrapper configuration" do
    expect([result.status.exitstatus, result.stderr]).to eq([
      0,
      "Warning: Calling HOMEBREW_FORCE_BREW_WRAPPER is deprecated! " \
      "Use your wrapper directly instead.\n",
    ])
  end

  test_each([nil, "0"]) do |opt_out|
    it "keeps the Homebrew executable through a wrapper with opt-out #{opt_out.inspect}" do
      wrapper = HOMEBREW_TEMP/"brew-wrapper"
      wrapper.write(<<~SH)
        #!/bin/bash
        export HOMEBREW_BREW_WRAPPER="$0"
        exec "#{HOMEBREW_BREW_FILE}" "$@"
      SH
      FileUtils.chmod 0755, wrapper
      ENV["HOMEBREW_FORCE_BREW_WRAPPER"] = wrapper.to_s
      ENV["HOMEBREW_NO_FORCE_BREW_WRAPPER"] = opt_out
      result = SystemCommand.run(wrapper, args: ["ruby", "-e", "puts HOMEBREW_BREW_FILE"])

      expect([result.status.exitstatus, result.stdout]).to eq([0, "#{HOMEBREW_BREW_FILE}\n"])
    end
  end

  it "turns deprecations into errors for developers" do
    ENV["HOMEBREW_DEVELOPER"] = "1"

    expect([result.status.exitstatus, result.stderr.lines.first]).to eq([
      1,
      "Error: Calling HOMEBREW_FORCE_BREW_WRAPPER is deprecated! Use your wrapper directly instead.\n",
    ])
  end

  test_each([nil, "/another/brew"]) do |wrapper|
    it "does not require a matching wrapper when the marker is #{wrapper.inspect}" do
      ENV["HOMEBREW_BREW_WRAPPER"] = wrapper

      expect(result).to be_a_success
    end
  end

  it "warns about obsolete custom help without printing it" do
    ENV.delete("HOMEBREW_FORCE_BREW_WRAPPER")
    ENV["HOMEBREW_FORCE_BREW_WRAPPER_HELP_MESSAGE"] = "-n"

    expect([result.status.exitstatus, result.stderr]).to eq([
      0,
      "Warning: Calling HOMEBREW_FORCE_BREW_WRAPPER_HELP_MESSAGE is deprecated! " \
      "Use custom help in your wrapper instead.\n",
    ])
  end

  it "warns about the obsolete opt-out without requiring a wrapper" do
    ENV.delete("HOMEBREW_FORCE_BREW_WRAPPER")
    ENV["HOMEBREW_NO_FORCE_BREW_WRAPPER"] = "0"

    expect([result.status.exitstatus, result.stderr]).to eq([
      0,
      "Warning: Calling HOMEBREW_NO_FORCE_BREW_WRAPPER is deprecated! " \
      "Use an environment without $HOMEBREW_NO_FORCE_BREW_WRAPPER instead.\n",
    ])
  end

  it "does nothing when no wrapper is required" do
    ENV.delete("HOMEBREW_FORCE_BREW_WRAPPER")

    expect([result.status.exitstatus, result.stderr]).to eq([0, ""])
  end

  it "does not check deprecated Ruby settings that the command does not read" do
    ENV.delete("HOMEBREW_FORCE_BREW_WRAPPER")
    ENV["HOMEBREW_BAT_THEME"] = "GitHub"

    expect([result.status.exitstatus, result.stderr]).to eq([0, ""])
  end

  it "does not check deprecated settings when displaying help" do
    ENV["HOMEBREW_DEVELOPER"] = "1"
    result = SystemCommand.run(HOMEBREW_BREW_FILE, args: ["commands", "--help"])

    expect([result.status.exitstatus, result.stderr]).to eq([0, ""])
  end

  it "does not check deprecated settings when an external command displays its own help" do
    command = HOMEBREW_TEMP/"brew-wrapper-test"
    command.write(<<~SH)
      #!/bin/bash
      printf '%s\\n' "$@"
    SH
    command.chmod(0755)
    ENV["HOMEBREW_PATH"] = PATH.new(ENV.fetch("PATH")).prepend(HOMEBREW_TEMP).to_s
    ENV["HOMEBREW_DEVELOPER"] = "1"
    result = SystemCommand.run(HOMEBREW_BREW_FILE, args: ["help", "wrapper-test"])

    expect([result.status.exitstatus, result.stdout, result.stderr]).to eq([0, "--help\n", ""])
  end

  it "reports unknown commands before checking deprecated settings" do
    ENV["HOMEBREW_DEVELOPER"] = "1"
    result = SystemCommand.run(HOMEBREW_BREW_FILE, args: ["wrapper-test-unknown"])

    expect([result.status.exitstatus, result.stderr.lines.grep(/Error:|Warning:/)]).to eq([
      1,
      ["Error: Invalid usage: Unknown command: brew wrapper-test-unknown\n"],
    ])
  end

  it "does not warn or enforce wrapper settings in shell-only commands" do
    ENV.delete("HOMEBREW_BREW_WRAPPER")
    result = SystemCommand.run(HOMEBREW_BREW_FILE, args: ["--version"])

    expect([result.status.exitstatus, result.stderr]).to eq([0, ""])
  end
end
