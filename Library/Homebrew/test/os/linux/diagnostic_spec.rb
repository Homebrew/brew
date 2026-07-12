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

    expect(checks.check_supported_architecture)
      .to match(/Your CPU architecture .+ is not supported/)
  end

  specify "#check_glibc_minimum_version" do
    allow(OS::Linux::Glibc).to receive(:below_minimum_version?).and_return(true)

    expect(checks.check_glibc_minimum_version)
      .to match(/Your system glibc .+ is too old/)
  end

  specify "#check_glibc_next_version" do
    allow(OS).to receive(:const_get).with(:LINUX_GLIBC_NEXT_CI_VERSION).and_return("2.39")
    allow(OS::Linux::Glibc).to receive_messages(below_ci_version?: false, system_version: Version.new("2.35"))
    allow(ENV).to receive(:[]).and_return(nil)

    expect(checks.check_glibc_next_version)
      .to match("Your system glibc 2.35 is older than 2.39")
  end

  specify "#check_kernel_minimum_version" do
    allow(OS::Linux::Kernel).to receive(:below_minimum_version?).and_return(true)

    expect(checks.check_kernel_minimum_version)
      .to match(/Your Linux kernel .+ is too old/)
  end

  specify "#check_for_installed_developer_tools explains system build tools" do
    allow(DevelopmentTools).to receive(:installed?).and_return(false)

    expect(checks.check_for_installed_developer_tools)
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
      expect(checks.check_linux_sandbox).to be_nil
    end
  end

  specify "#check_linux_sandbox returns nil when the Linux sandbox is available" do
    allow(Sandbox).to receive(:state).and_return(:available)
    expect(Sandbox).not_to receive(:failure_reason)

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      expect(checks.check_linux_sandbox).to be_nil
    end
  end

  specify "#check_linux_sandbox returns nil inside Docker" do
    allow(OS::Linux).to receive(:inside_docker?).and_return(true)
    expect(Sandbox).not_to receive(:state)

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      expect(checks.check_linux_sandbox).to be_nil
    end
  end

  specify "#check_linux_sandbox describes missing Bubblewrap" do
    allow(Sandbox).to receive_messages(
      state:                   :missing,
      failure_reason:          "Bubblewrap is required to use the Linux sandbox but was not found.",
      sandbox_install_command: "sudo apt-get install bubblewrap",
    )

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      message = checks.check_linux_sandbox.to_s

      expect(message)
        .to include(
          "Bubblewrap is required to use the Linux sandbox but was not found.",
          "Install Bubblewrap and ensure a rootless `bwrap` executable is available on `PATH`.",
          "On this system, install it with:",
          "  sudo apt-get install bubblewrap",
          "export HOMEBREW_NO_SANDBOX_LINUX=1",
        )
      expect(message).not_to include("sysctl")
      expect(message).to end_with("  export HOMEBREW_NO_SANDBOX_LINUX=1\n")
    end
  end

  specify "#check_linux_sandbox describes setuid Bubblewrap" do
    allow(Sandbox).to receive_messages(
      state:          :setuid,
      failure_reason: "All found `bwrap` executables are setuid.",
    )

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      message = checks.check_linux_sandbox.to_s

      expect(message)
        .to include(
          "All found `bwrap` executables are setuid.",
          "Homebrew's Linux sandbox requires a rootless `bwrap` executable.",
          "Install a non-setuid Bubblewrap or put it earlier on `PATH`.",
          "export HOMEBREW_NO_SANDBOX_LINUX=1",
        )
      expect(message).not_to include("sysctl")
      expect(message).to end_with("  export HOMEBREW_NO_SANDBOX_LINUX=1\n")
    end
  end

  specify "#check_linux_sandbox describes Bubblewrap configuration" do
    allow(Sandbox).to receive_messages(
      state:          :unavailable,
      failure_reason: "Bubblewrap is installed but cannot create a rootless sandbox.",
    )

    with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) do
      message = checks.check_linux_sandbox.to_s

      expect(message)
        .to include(
          "Bubblewrap is installed but cannot create a rootless sandbox.",
          "Homebrew's Linux sandbox requires rootless Bubblewrap and unprivileged",
          "sudo sysctl -w kernel.unprivileged_userns_clone=1",
          "Allows unprivileged processes to create user namespaces.",
          "sudo sysctl -w user.max_user_namespaces=28633",
          "Allows each user to allocate enough user namespaces.",
          "sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true",
          "Allows unprivileged user namespaces on AppArmor-enabled systems",
          "export HOMEBREW_NO_SANDBOX_LINUX=1",
        )
      expect(message).to end_with("  export HOMEBREW_NO_SANDBOX_LINUX=1\n")
    end
  end

  specify "#check_for_symlinked_home" do
    allow(File).to receive(:symlink?).with("/home").and_return(true)

    expect(checks.check_for_symlinked_home)
      .to include("Your /home directory is a symlink")
  end
end
