# typed: true
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

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

  specify "#check_for_symlinked_home" do
    allow(File).to receive(:symlink?).with("/home").and_return(true)

    expect(checks.check_for_symlinked_home)
      .to match(%r{Your /home directory is a symlink})
  end
end
