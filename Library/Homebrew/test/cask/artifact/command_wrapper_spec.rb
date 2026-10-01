# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::CommandWrapper, :cask do
  let(:cask) do
    Cask::Cask.new("with-command-wrapper") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      command_wrapper "example",
                      executable: "/Applications/Example.app/Contents/MacOS/example",
                      args:       ["--cli", "batch mode"],
                      env:        { "EXAMPLE_MODE" => "batch" }
    end
  end
  let(:artifact) { cask.artifacts.find { |candidate| candidate.is_a?(described_class) } }
  let(:target) { cask.config.binarydir/"example" }
  let(:custom_target) { cask.config.binarydir/"custom" }

  before do
    cask.staged_path.mkpath
    target.dirname.mkpath
  end

  after do
    FileUtils.rm_f target
    FileUtils.rm_f custom_target
    FileUtils.rm_rf cask.staged_path
  end

  it "writes and links an executable command wrapper" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(target).to be_a_symlink.and have_attributes(
      read:        <<~BASH,
        #!/bin/bash
        EXAMPLE_MODE="batch" exec "/Applications/Example.app/Contents/MacOS/example" --cli batch\\ mode "$@"
      BASH
      executable?: true,
      readlink:    cask.staged_path/".homebrew-command-wrappers/example",
    )
  end

  it "lists the target in a dry run without writing the wrapper" do
    expect do
      artifact.install_phase(command: NeverSudoSystemCommand, force: false, dry_run: true)
    end.to output("#{target}\n").to_stdout

    expect(artifact.source).not_to exist
  end

  it "serialises the wrapper definition" do
    expect(artifact.to_args).to eq([
      "example",
      {
        executable: "/Applications/Example.app/Contents/MacOS/example",
        args:       ["--cli", "batch mode"],
        env:        { "EXAMPLE_MODE" => "batch" },
      },
    ])
  end

  it "shell-escapes a single non-array argument" do
    wrapper = described_class.from_args(cask, "custom",
                                        executable: "/usr/bin/example",
                                        args:       "two words; true")
    wrapper.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(custom_target.read).to eq(<<~BASH)
      #!/bin/bash
      exec "/usr/bin/example" two\\ words\\;\\ true "$@"
    BASH
  end

  it "serialises Pathname arguments and symbol environment keys as plain strings" do
    wrapper = described_class.from_args(cask, "custom",
                                        executable: Pathname("/usr/bin/example"),
                                        args:       Pathname("/etc/example.conf"),
                                        env:        { EXAMPLE_MODE: Pathname("/var/example") })

    expect(wrapper.to_args).to eq([
      "custom",
      {
        executable: "/usr/bin/example",
        args:       ["/etc/example.conf"],
        env:        { "EXAMPLE_MODE" => "/var/example" },
      },
    ])
  end

  it "accepts custom wrapper content" do
    content = "#!/bin/sh\nexit 1\n"
    custom_artifact = described_class.from_args(cask, "custom", content:)
    custom_artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(custom_target).to be_a_symlink.and have_attributes(read: content, executable?: true)
  end

  it "serialises custom wrapper content" do
    custom_artifact = described_class.from_args(cask, "custom", content: "#!/bin/sh\nexit 1\n")

    expect(custom_artifact.to_args).to eq([
      "custom",
      { content: "#!/bin/sh\nexit 1\n" },
    ])
  end

  it "rejects missing content and executable" do
    expect do
      described_class.from_args(cask, "other")
    end.to raise_error(Cask::CaskInvalidError, /requires content or executable/)
  end

  it "rejects options that are not a hash" do
    expect do
      described_class.from_args(cask, "other", "example")
    end.to raise_error(Cask::CaskInvalidError, /requires a hash of options/)
  end

  it "rejects `false` options" do
    expect do
      described_class.from_args(cask, "other", false)
    end.to raise_error(Cask::CaskInvalidError, /requires a hash of options/)
  end

  it "rejects command names containing path components" do
    expect do
      described_class.from_args(cask, "../other", executable: "example")
    end.to raise_error(Cask::CaskInvalidError, /requires a command name without path components/)
  end

  it "rejects content with an executable" do
    expect do
      described_class.from_args(cask, "other", content: "#!/bin/sh\n", executable: "example")
    end.to raise_error(Cask::CaskInvalidError, /content or executable, not both/)
  end
end
