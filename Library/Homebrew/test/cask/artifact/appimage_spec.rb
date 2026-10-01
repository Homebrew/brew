# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AppImage, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("with-appimage")) }
  let(:command) { NeverSudoSystemCommand }
  let(:adopt) { false }
  let(:force) { false }
  let(:auto_updates) { false }
  let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

  let(:source_path) { cask.staged_path.join("naked.AppImage") }
  let(:target_path) { Pathname(cask.config.appimagedir).join("naked.AppImage") }

  let(:install_phase) { artifact.install_phase(command:, adopt:, force:, auto_updates:) }
  let(:uninstall_phase) { artifact.uninstall_phase(command:, force:) }

  let(:setup_cask) { InstallHelper.install_without_artifacts(cask) }

  before do
    setup_cask
  end

  describe "install_phase" do
    it "moves the real AppImage to appimagedir and back-links from the Caskroom" do
      install_phase

      expect(target_path).to be_a_file
      expect(target_path).not_to be_a_symlink
      expect(source_path).to be_a_symlink
      expect(source_path.readlink).to eq(target_path)
    end

    it "makes a non-executable AppImage executable at the target" do
      FileUtils.chmod "-x", source_path
      expect(source_path).not_to be_executable

      install_phase

      expect(target_path).to be_executable
    end

    describe "when a self-updater replaces the target in place" do
      it "keeps the Caskroom back-link valid and pointing at the new contents" do
        install_phase

        replacement = "#!/bin/sh\necho \"AppImage v2\"\n"
        File.write(target_path, replacement)

        expect(source_path).to be_a_symlink
        expect(source_path.readlink).to exist
        expect(File.read(source_path)).to eq(replacement)
      end
    end

    describe "given the adopt option" do
      let(:adopt) { true }

      before do
        target_path.dirname.mkpath
        FileUtils.cp source_path, target_path
      end

      it "adopts an identical existing AppImage without auto_updates" do
        install_phase

        expect(target_path).to be_a_file
        expect(source_path).to be_a_symlink
      end

      describe "when the cask auto_updates" do
        let(:auto_updates) { true }

        before do
          File.write(target_path, "#!/bin/sh\necho \"AppImage v2\"\n")
        end

        it "adopts the existing AppImage without comparing contents" do
          install_phase

          expect(target_path).to be_a_file
          expect(source_path).to be_a_symlink
        end
      end
    end
  end

  describe "uninstall_phase" do
    it "removes the target AppImage" do
      install_phase

      expect(target_path).to exist

      uninstall_phase

      expect(target_path).not_to exist
    end

    describe "migrating from the old Symlinked layout" do
      before do
        # Recreate the pre-inversion on-disk state: a real file in the
        # versioned Caskroom source and a symlink at the target pointing back.
        target_path.dirname.mkpath
        FileUtils.ln_sf source_path, target_path
      end

      it "removes both the target symlink and the Caskroom file without raising" do
        expect(source_path).to be_a_file
        expect(target_path).to be_a_symlink

        expect { uninstall_phase }.not_to raise_error

        expect(target_path).not_to exist
        expect(source_path).not_to exist
      end

      describe "when a self-updater already deleted the versioned source" do
        before do
          # The exact breakage this stanza fixes: `source` is gone and the
          # `target` symlink is left dangling.
          source_path.delete
        end

        it "removes the dangling target without raising" do
          expect(target_path).to be_a_symlink
          expect(target_path).not_to exist
          expect(source_path).not_to exist

          expect { uninstall_phase }.not_to raise_error

          expect(target_path).not_to be_a_symlink
          expect(target_path).not_to exist
        end
      end

      describe "during an upgrade" do
        let(:uninstall_phase) { artifact.uninstall_phase(command:, force:, upgrade: true) }

        it "removes the target symlink but preserves the source for the backup" do
          expect(source_path).to be_a_file
          expect(target_path).to be_a_symlink

          expect { uninstall_phase }.not_to raise_error

          expect(target_path).not_to exist
          expect(source_path).to be_a_file
        end
      end
    end
  end

  describe "summary" do
    let(:contents) { artifact.summarize_installed }

    it "returns the correct english_description" do
      expect(artifact.class.english_description).to eq("App Images")
    end

    describe "AppImage is missing" do
      let(:setup_cask) { nil }

      it "returns a warning and the supposed path to the AppImage" do
        expect(contents).to match(/.*Missing App Image.*: #{target_path}/)
      end
    end

    describe "AppImage is correctly installed" do
      it "returns the path to the AppImage" do
        install_phase

        expect(contents).to eq("#{target_path} (#{target_path.abv})")
      end
    end
  end
end
