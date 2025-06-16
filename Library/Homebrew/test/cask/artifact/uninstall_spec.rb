# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Uninstall, :cask do
  describe "#uninstall_phase" do
    include_examples "#uninstall_phase or #zap_phase"
  end

  describe "#post_uninstall_phase" do
    subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

    context "when using :rmdir" do
      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-rmdir")) }
      let(:empty_directory) { Pathname.new("#{TEST_TMPDIR}/empty_directory_path") }
      let(:empty_directory_tree) { empty_directory.join("nested", "empty_directory_path") }
      let(:ds_store) { empty_directory.join(".DS_Store") }

      before do
        empty_directory_tree.mkpath
        FileUtils.touch ds_store
      end

      after do
        FileUtils.rm_rf empty_directory
      end

      it "is supported" do
        expect(empty_directory_tree).to exist
        expect(ds_store).to exist

        artifact.post_uninstall_phase(command: fake_system_command)

        expect(ds_store).not_to exist
        expect(empty_directory).not_to exist
      end
    end
  end
end
