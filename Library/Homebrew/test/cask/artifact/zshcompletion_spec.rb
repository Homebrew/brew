# frozen_string_literal: true

RSpec.describe Cask::Artifact::ZshCompletion, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_token) }

  context "with install" do
    let(:install_phase) do
      lambda do
        cask.artifacts.select { |a| a.is_a?(described_class) }.each do |artifact|
          artifact.install_phase(command: NeverSudoSystemCommand, force: false)
        end
      end
    end

    let(:source_path) { cask.staged_path.join("_test") }
    let(:target_path) { cask.config.zsh_completion.join("_test") }
    let(:full_source_path) { cask.staged_path.join("test.zsh-completion") }
    let(:full_target_path) { cask.config.zsh_completion.join("_test") }

    before do
      InstallHelper.install_without_artifacts(cask)
    end

    context "with completion" do
      let(:cask_token) { "with-shellcompletion" }

      it "links the completion to the proper directory" do
        install_phase.call

        expect(File).to be_identical target_path, source_path
      end
    end

    context "with long completion" do
      let(:cask_token) { "with-shellcompletion-long" }

      it "links the completion to the proper directory" do
        install_phase.call

        expect(File).to be_identical full_target_path, full_source_path
      end
    end
  end
end
