# frozen_string_literal: true

describe Cask::Artifact::Suite, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("with-suite")) }

  let(:install_phase) do
    lambda do
      cask.artifacts.select { |a| a.is_a?(described_class) }.each do |artifact|
        artifact.install_phase(command: NeverSudoSystemCommand, force: false)
      end
    end
  end

  let(:target_path) { cask.config.appdir.join("Caffeine") }
  let(:source_path) { cask.staged_path.join("Caffeine") }

  before do
    InstallHelper.install_without_artifacts(cask)
  end

  it "creates a suite containing the expected app" do
    install_phase.call

    expect(target_path.join("Caffeine.app")).to exist
  end

  it "avoids clobbering an existing suite by moving over it" do
    target_path.mkpath

    expect do
      install_phase.call
    end.to raise_error(Cask::CaskError)

    expect(source_path).to be_a_directory
    expect(target_path).to be_a_directory
    expect(File.identical?(source_path, target_path)).to be false
  end
end
