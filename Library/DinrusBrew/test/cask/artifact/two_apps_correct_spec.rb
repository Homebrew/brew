# frozen_string_literal: true

RSpec.describe Cask::Artifact::App, :cask do
  describe "multiple apps" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-two-apps-correct")) }

    let(:install_phase) do
      cask.artifacts.select { |a| a.is_a?(described_class) }.each do |artifact|
        artifact.install_phase(command: NeverSudoSystemCommand, force: false)
      end
    end

    let(:source_path_mini) { cask.staged_path.join("Caffeine Mini.app") }
    let(:target_path_mini) { cask.config.appdir.join("Caffeine Mini.app") }

    let(:source_path_pro) { cask.staged_path.join("Caffeine Pro.app") }
    let(:target_path_pro) { cask.config.appdir.join("Caffeine Pro.app") }

    before do
      InstallHelper.install_without_artifacts(cask)
    end

    it "installs both apps using the proper target directory" do
      install_phase

      expect(target_path_mini).to be_a_directory
      expect(source_path_mini).to be_a_symlink

      expect(target_path_pro).to be_a_directory
      expect(source_path_pro).to be_a_symlink
    end

    describe "when apps are in a subdirectory" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-two-apps-subdir")) }

      let(:source_path_mini) { cask.staged_path.join("Caffeines", "Caffeine Mini.app") }
      let(:source_path_pro) { cask.staged_path.join("Caffeines", "Caffeine Pro.app") }

      it "installs both apps using the proper target directory" do
        install_phase

        expect(target_path_mini).to be_a_directory
        expect(source_path_mini).to be_a_symlink

        expect(target_path_pro).to be_a_directory
        expect(source_path_pro).to be_a_symlink
      end
    end

    it "only uses apps when they are specified" do
      FileUtils.cp_r source_path_mini, source_path_mini.sub("Caffeine Mini.app", "Caffeine Deluxe.app")

      install_phase

      expect(target_path_mini).to be_a_directory
      expect(source_path_mini).to be_a_symlink

      expect(cask.config.appdir.join("Caffeine Deluxe.app")).not_to exist
      expect(cask.staged_path.join("Caffeine Deluxe.app")).to exist
    end

    describe "avoids clobbering an existing app" do
      it "when the first app of two already exists" do
        target_path_mini.mkpath

        expect do
          expect { install_phase }.to output(<<~EOS).to_stdout
            ==> Moving App 'Caffeine Pro.app' to '#{target_path_pro}'
          EOS
        end.to raise_error(Cask::CaskError, "It seems there is already an App at '#{target_path_mini}'.")

        expect(source_path_mini).to be_a_directory
        expect(target_path_mini).to be_a_directory
        expect(File.identical?(source_path_mini, target_path_mini)).to be false
      end

      it "when the second app of two already exists" do
        target_path_pro.mkpath

        expect do
          expect { install_phase }.to output(<<~EOS).to_stdout
            ==> Moving App 'Caffeine Mini.app' to '#{target_path_mini}'
          EOS
        end.to raise_error(Cask::CaskError, "It seems there is already an App at '#{target_path_pro}'.")

        expect(source_path_pro).to be_a_directory
        expect(target_path_pro).to be_a_directory
        expect(File.identical?(source_path_pro, target_path_pro)).to be false
      end
    end
  end
end
