# frozen_string_literal: true

RSpec.describe Cask::Artifact::Symlinked, :cask do
  # Test the formula conflict detection functionality that applies to all symlinked artifacts
  describe "#conflicting_formula" do
    let(:cask) do
      Cask::CaskLoader.load(cask_path("with-binary")).tap do |cask|
        InstallHelper.install_without_artifacts(cask)
      end
    end

    let(:binary_artifact) { cask.artifacts.find { |a| a.is_a?(Cask::Artifact::Binary) } }
    let(:binarydir) { cask.config.binarydir }
    let(:target_path) { binarydir.join("binary") }

    around do |example|
      binarydir.mkpath

      example.run
    ensure
      FileUtils.rm_f target_path
      FileUtils.rmdir binarydir
      # Clean up the fake formula directory
      FileUtils.rm_rf(HOMEBREW_CELLAR/"with-binary") if (HOMEBREW_CELLAR/"with-binary").exist?
    end

    context "when target is already linked from a formula" do
      it "detects the conflict and skips linking with warning" do
        # Create a fake formula directory structure
        formula_cellar_path = HOMEBREW_CELLAR/"with-binary/1.0.0/bin"
        formula_cellar_path.mkpath
        formula_binary_path = formula_cellar_path/"binary"
        FileUtils.touch formula_binary_path

        # Create symlink from the expected location to the formula binary
        target_path.make_symlink(formula_binary_path)

        stderr = <<~EOS
          Warning: It seems there is already a Binary at '#{target_path}' from formula with-binary; skipping link.
        EOS

        expect do
          binary_artifact.install_phase(command: NeverSudoSystemCommand, force: false)
        end.to output(stderr).to_stderr

        expect(target_path).to be_a_symlink
        expect(target_path.readlink).to eq(formula_binary_path)
      end
    end

    context "when target doesn't exist" do
      it "proceeds with normal installation" do
        expect do
          binary_artifact.install_phase(command: NeverSudoSystemCommand, force: false)
        end.not_to raise_error

        expect(target_path).to be_a_symlink
        expect(target_path.readlink).to exist
      end
    end
  end
end
