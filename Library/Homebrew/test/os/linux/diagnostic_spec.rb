# typed: true
# frozen_string_literal: true

require "diagnostic"
require "sandbox"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  before do
    allow(OS::Linux).to receive(:inside_docker?).and_return(false)
  end

  specify "#check_supported_architecture" do
    allow(Hardware::CPU).to receive(:type).and_return(:arm64)

    expect(checks.check_supported_architecture&.to_s)
      .to match(/Your CPU architecture .+ is not supported/)
  end

  specify "#check_glibc_minimum_version" do
    allow(OS::Linux::Glibc).to receive(:below_minimum_version?).and_return(true)

    expect(checks.check_glibc_minimum_version&.to_s)
      .to match(/Your system glibc .+ is too old/)
  end

  specify "#check_glibc_next_version" do
    allow(OS).to receive(:const_get).with(:LINUX_GLIBC_NEXT_CI_VERSION).and_return("2.39")
    allow(OS::Linux::Glibc).to receive_messages(below_ci_version?: false, system_version: Version.new("2.35"))
    allow(ENV).to receive(:[]).and_return(nil)

    expect(checks.check_glibc_next_version&.to_s)
      .to match("Your system glibc 2.35 is older than 2.39")
  end

  specify "#check_kernel_minimum_version" do
    allow(OS::Linux::Kernel).to receive(:below_minimum_version?).and_return(true)

    expect(checks.check_kernel_minimum_version&.to_s)
      .to match(/Your Linux kernel .+ is too old/)
  end

  specify "#check_for_installed_developer_tools explains system build tools" do
    allow(DevelopmentTools).to receive(:installed?).and_return(false)

    expect(checks.check_for_installed_developer_tools&.to_s)
      .to include(
        "No developer tools installed.",
        "Install a system C compiler and the standard development tools",
        "https://docs.brew.sh/Homebrew-on-Linux#requirements",
      )
  end

  describe ".custom_installation_instructions" do
    it "points at brew install gcc" do
      expect(DevelopmentTools.custom_installation_instructions).to include("brew install gcc")
    end
  end

  specify "#fatal_build_from_source_checks" do
    expect(checks.fatal_build_from_source_checks).not_to include("check_linux_sandbox")
  end

  specify "#check_linux_sandbox returns nil when Linux sandboxing is disabled" do
    expect(Sandbox).not_to receive(:failure_reason)

    with_env(HOMEBREW_NO_SANDBOX_LINUX: "1") do
      expect(checks.check_linux_sandbox&.to_s).to be_nil
    end
  end

  specify "#check_linux_sandbox returns nil when the Linux sandbox is available" do
    allow(Sandbox).to receive(:state).and_return(:available)
    expect(Sandbox).not_to receive(:failure_reason)

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      expect(checks.check_linux_sandbox&.to_s).to be_nil
    end
  end

  specify "#check_linux_sandbox returns nil inside Docker outside GitHub Actions" do
    allow(OS::Linux).to receive(:inside_docker?).and_return(true)
    expect(Sandbox).not_to receive(:state)

    with_env(GITHUB_ACTIONS: nil, HOMEBREW_NO_SANDBOX_LINUX: nil) do
      expect(checks.check_linux_sandbox&.to_s).to be_nil
    end
  end

  specify "#check_linux_sandbox describes unsupported Landlock" do
    allow(Sandbox).to receive_messages(
      state:          :unsupported,
      failure_reason: "Landlock is not supported by this Linux kernel.",
    )

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      message = checks.check_linux_sandbox&.to_s

      expect(message)
        .to include(
          "Landlock is not supported by this Linux kernel.",
          "Homebrew's Linux sandbox requires a kernel with Landlock enabled.",
          "export HOMEBREW_NO_SANDBOX_LINUX=1",
        )
      expect(message).to end_with("  export HOMEBREW_NO_SANDBOX_LINUX=1")
    end
  end

  specify "#check_linux_sandbox describes missing Fiddle" do
    allow(Sandbox).to receive_messages(
      state:          :missing_fiddle,
      failure_reason: "Landlock requires Ruby's bundled Fiddle library.",
    )

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      message = checks.check_linux_sandbox&.to_s

      expect(message)
        .to include(
          "Landlock requires Ruby's bundled Fiddle library.",
          "Run Homebrew with its vendored Ruby, which includes Fiddle.",
          "export HOMEBREW_NO_SANDBOX_LINUX=1",
        )
      expect(message).not_to include("kernel with Landlock")
    end
  end

  specify "#check_linux_sandbox describes unavailable Landlock inside Docker on GitHub Actions" do
    allow(OS::Linux).to receive(:inside_docker?).and_return(true)
    allow(Sandbox).to receive_messages(
      state:          :disabled,
      failure_reason: "Landlock is disabled by this Linux kernel.",
    )

    with_env(GITHUB_ACTIONS: "true", HOMEBREW_NO_SANDBOX_LINUX: nil) do
      expect(checks.check_linux_sandbox&.to_s).to include("Landlock is disabled by this Linux kernel.")
    end
  end

  specify "#check_for_symlinked_home" do
    allow(File).to receive(:symlink?).with("/home").and_return(true)

    expect(checks.check_for_symlinked_home&.to_s)
      .to include("Your /home directory is a symlink")
  end
end
