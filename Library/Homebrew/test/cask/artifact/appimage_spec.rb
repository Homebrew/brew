# frozen_string_literal: true

RSpec.describe Cask::Artifact::AppImage, :cask do
  let(:cask) do
    Cask::CaskLoader.load(cask_path("with-appimage")).tap do |cask|
      InstallHelper.install_without_artifacts(cask)
    end
  end
  let(:artifacts) { cask.artifacts.select { |a| a.is_a?(described_class) } }
  let(:appimagedir) { cask.config.appimagedir }
  let(:expected_path) { appimagedir.join("binary") }

  around do |example|
    appimagedir.mkpath

    example.run
  ensure
    FileUtils.rm_f expected_path
    FileUtils.rmdir appimagedir
  end

  it "links the appimage to the proper directory" do
    artifacts.each do |artifact|
      artifact.install_phase(command: NeverSudoSystemCommand, force: false)
    end

    expect(expected_path).to be_a_symlink
    expect(expected_path.readlink).to exist
  end

  it "creates parent directory if it doesn't exist" do
    FileUtils.rmdir appimagedir

    artifacts.each do |artifact|
      artifact.install_phase(command: NeverSudoSystemCommand, force: false)
    end

    expect(expected_path.exist?).to be true
  end
end
