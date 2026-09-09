# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::Package, :cask, :needs_linux do
  let(:cask) { Cask::CaskLoader.load(cask_path("with-package")) }
  let(:fake_system_command) { class_double(SystemCommand) }

  before do
    InstallHelper.install_without_artifacts(cask)
  end

  describe ".from_args" do
    it "creates a Package artifact with the specified path" do
      artifact = described_class.from_args(cask, "caffeine_1.2.3_amd64.deb")
      expect(artifact.path).to eq("caffeine_1.2.3_amd64.deb")
    end
  end

  describe "#summarize" do
    it "returns the package path" do
      artifact = cask.artifacts.find { |a| a.is_a?(described_class) }
      expect(artifact.summarize).to eq("caffeine_1.2.3_amd64.deb")
    end
  end

  describe "install_phase" do
    it "runs dpkg -i with sudo for .deb files" do
      artifact = cask.artifacts.find { |a| a.is_a?(described_class) }

      expect(fake_system_command).to receive(:run!).with(
        "sudo",
        args:         ["dpkg", "-i", cask.staged_path.join("caffeine_1.2.3_amd64.deb")],
        print_stdout: true,
      )

      artifact.install_phase(command: fake_system_command)
    end
  end

  describe "uninstall_phase" do
    it "queries package name and runs dpkg --purge with sudo for .deb files" do
      artifact = cask.artifacts.find { |a| a.is_a?(described_class) }

      query_result = instance_double(SystemCommand::Result, stdout: "caffeine\n")
      expect(fake_system_command).to receive(:run).with(
        "dpkg-deb",
        args:         ["--showformat", "${Package}", "-W", cask.staged_path.join("caffeine_1.2.3_amd64.deb")],
        print_stderr: false,
      ).and_return(query_result)

      expect(fake_system_command).to receive(:run!).with(
        "sudo",
        args:         ["dpkg", "--purge", "--force-depends", "caffeine"],
        print_stdout: true,
      )

      artifact.uninstall_phase(command: fake_system_command)
    end
  end
end
