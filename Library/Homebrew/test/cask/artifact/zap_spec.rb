# typed: true
# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Zap, :cask do
  describe "::from_args" do
    let(:cask) { Cask::Cask.new("zap-not-required") }

    it "serialises `:not_required` as an empty stanza that older versions can load" do
      expect(described_class.from_args(cask, :not_required).to_args).to be_empty
    end

    it "rejects `:not_required` with directives" do
      expect { described_class.from_args(cask, :not_required, trash: "~/Library/Foo") }
        .to raise_error(Cask::CaskInvalidError, /:not_required/)
    end
  end

  describe "directive dispatch" do
    include_examples "uninstall/zap directive dispatch"

    context "when using :rmdir" do
      subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-zap-rmdir")) }
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

        described_class.dispatch_directives([artifact], command: fake_system_command, deferred: true)

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
          expect do
            described_class.dispatch_directives([artifact], command: fake_system_command, deferred: true)
          end.not_to raise_error

          expect(empty_directory).to be_a_symlink
          expect(target.join("nested")).to be_a_directory
        end
      end
    end
  end
end
