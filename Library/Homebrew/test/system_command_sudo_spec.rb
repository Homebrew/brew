# typed: strict
# frozen_string_literal: true

require "system_command"

RSpec.describe SystemCommand do
  it "checks sudo access before the first sudo command only" do
    ENV.delete("HOMEBREW_NO_SUDO")
    ENV.delete("HOMEBREW_SUDO_CHECKED")

    expect(described_class).to receive(:run)
      .with("/bin/bash", args: [HOMEBREW_LIBRARY_PATH/"utils/sudo.sh"], print_stderr: false)
      .once.and_return(instance_double(SystemCommand::Result, success?: true))

    2.times { described_class.new("true", sudo: true).command }
  end

  it "does not probe sudo for a successful optional operation" do
    ENV.delete("HOMEBREW_NO_SUDO")
    ENV.delete("HOMEBREW_SUDO_CHECKED")

    allow(described_class).to receive(:run).and_call_original
    expect(described_class).not_to receive(:run).with("/bin/bash", any_args)

    described_class.run!("/usr/bin/true", sudo: nil)
  end

  it "preserves the original failure when sudo access is denied" do
    ENV.delete("HOMEBREW_NO_SUDO")
    ENV.delete("HOMEBREW_SUDO_CHECKED")
    allow(described_class).to receive(:run).and_call_original
    allow(described_class).to receive(:run)
      .with("/bin/bash", args: [HOMEBREW_LIBRARY_PATH/"utils/sudo.sh"], print_stderr: false)
      .and_return(instance_double(SystemCommand::Result, success?: false))

    expect { described_class.run!("/usr/bin/false", sudo: nil, print_stderr: false) }
      .to raise_error(ErrorDuringExecution, %r{`/usr/bin/env /usr/bin/false`})
  end

  it "rejects sudo commands when sudo is disabled" do
    ENV["HOMEBREW_NO_SUDO"] = "1"

    expect { described_class.new("true", sudo: true).command }
      .to raise_error(ErrorDuringExecution, /sudo is disabled by HOMEBREW_NO_SUDO/)
  end

  it "preserves sudo commands when sudo is enabled" do
    ENV.delete("HOMEBREW_NO_SUDO")

    expect(described_class.new("true", sudo: true).command).to eq(["/usr/bin/sudo", "-E", "--", "true"])
  end

  it "tries optional elevation without sudo first" do
    ENV.delete("HOMEBREW_NO_SUDO")

    expect(described_class.run!("/usr/bin/true", sudo: nil).success?).to be true
  end

  it "retries a failed optional operation with sudo" do
    ENV.delete("HOMEBREW_NO_SUDO")
    attempts = []
    allow(described_class).to receive(:new) do |_, **options|
      attempts << options.fetch(:sudo)
      instance_double(described_class, run!: instance_double(SystemCommand::Result, success?: options.fetch(:sudo)))
    end

    described_class.run("chmod", sudo: nil)

    expect(attempts).to eq([false, true])
  end

  it "keeps the original failure when optional elevation is disabled" do
    ENV["HOMEBREW_NO_SUDO"] = "1"

    expect { described_class.run!("/usr/bin/false", sudo: nil, print_stderr: false) }
      .to raise_error(ErrorDuringExecution, %r{/usr/bin/false})
  end
end
