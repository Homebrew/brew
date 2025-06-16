# frozen_string_literal: true

RSpec.describe Cask::Utils do
  let(:command) { NeverSudoSystemCommand }
  let(:dir) { mktmpdir }
  let(:path) { dir/"a/b/c" }
  let(:link) { dir/"link" }

  describe "::gain_permissions_mkpath" do
    it "creates a directory" do
      expect(path).not_to exist
      described_class.gain_permissions_mkpath(path, command:)
      expect(path).to be_a_directory
      described_class.gain_permissions_mkpath(path, command:)
      expect(path).to be_a_directory
    end

    context "when parent directory is not writable" do
      it "creates a directory with `sudo`" do
        FileUtils.chmod "-w", dir
        expect(dir).not_to be_writable

        expect(command).to receive(:run!).exactly(:once).and_wrap_original do |original, *args, **options|
          FileUtils.chmod "+w", dir
          original.call(*args, **options)
          FileUtils.chmod "-w", dir
        end

        expect(path).not_to exist
        described_class.gain_permissions_mkpath(path, command:)
        expect(path).to be_a_directory
        described_class.gain_permissions_mkpath(path, command:)
        expect(path).to be_a_directory

        expect(dir).not_to be_writable
        FileUtils.chmod "+w", dir
      end
    end
  end

  describe "::gain_permissions_remove" do
    it "removes the symlink, not the file it points to" do
      path.dirname.mkpath
      FileUtils.touch path
      FileUtils.ln_s path, link

      expect(path).to be_a_file
      expect(link).to be_a_symlink
      expect(link.readlink).to eq path

      described_class.gain_permissions_remove(link, command:)

      expect(path).to be_a_file
      expect(link).not_to exist

      described_class.gain_permissions_remove(path, command:)

      expect(path).not_to exist
    end

    it "removes the symlink, not the directory it points to" do
      path.mkpath
      FileUtils.ln_s path, link

      expect(path).to be_a_directory
      expect(link).to be_a_symlink
      expect(link.readlink).to eq path

      described_class.gain_permissions_remove(link, command:)

      expect(path).to be_a_directory
      expect(link).not_to exist

      described_class.gain_permissions_remove(path, command:)

      expect(path).not_to exist
    end
  end
end
