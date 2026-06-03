# typed: strict
# frozen_string_literal: true

require "install"

RSpec.describe Homebrew::Install do
  specify "::perform_preinstall_checks runs non-fatal preinstall diagnostics" do
    allow(Homebrew::Install).to receive(:check_prefix)
    allow(Homebrew::Install).to receive(:check_cpu)
    allow(Homebrew::Install).to receive(:attempt_directory_creation)

    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:supported_configuration_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:preinstall_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:fatal_preinstall_checks)
      .ordered

    Homebrew::Install.send(:perform_preinstall_checks)
  end
end
