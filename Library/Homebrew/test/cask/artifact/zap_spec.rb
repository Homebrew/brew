# typed: true
# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Zap, :cask do
  describe "#zap_phase" do
    include_examples "#uninstall_phase or #zap_phase"

    context "when using :rmdir" do
      subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:cask) { Cask::CaskLoader.load(cask_path("with-zap-rmdir")) }
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

        artifact.zap_phase(command: fake_system_command)

        expect(ds_store).not_to exist
        expect(empty_directory).not_to exist
      end

      context "when the directory is a symlink" do
        let(:target) { Pathname.new("#{TEST_TMPDIR}/rmdir_symlink_target") }

        before do
          FileUtils.rm_rf empty_directory
          target.join("nested").mkpath
          FileUtils.ln_s target, empty_directory
        end

        after { FileUtils.rm_rf target }

        it "leaves the link and its target alone" do
          expect { artifact.zap_phase(command: fake_system_command) }.not_to raise_error

          expect(empty_directory).to be_a_symlink
          expect(target.join("nested")).to be_a_directory
        end
      end
    end
  end
end
