# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Utils do
  let(:command) { NeverSudoSystemCommand }
  let(:dir) { mktmpdir }
  let(:path) { dir/"a/b/c" }
  let(:link) { dir/"link" }
  let(:file) { dir/"file" }
  let(:foreign_uid) { Process.euid + 1 }

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

  describe "::gain_permissions_rmdir" do
    it "changes the permissions of the symlink, not the directory it points to" do
      path.mkpath
      (path/"sub").mkpath
      path.chmod(0500)
      FileUtils.ln_s path, link

      expect { described_class.gain_permissions_rmdir(link, command:) }.to raise_error(Errno::ENOTDIR)

      expect(path.stat.mode & 0777).to eq 0500
      expect(path/"sub").to be_a_directory

      path.chmod(0700)
    end
  end

  describe "::ownership_problem?" do
    it "is false when the path is owned by the current user" do
      FileUtils.touch file

      expect(described_class.ownership_problem?(file, recursive: false)).to be false
    end

    it "is true when the path is owned by another user" do
      FileUtils.touch file
      allow(Process).to receive(:euid).and_return(foreign_uid)

      expect(described_class.ownership_problem?(file, recursive: false)).to be true
    end

    it "stats the symlink itself rather than its target" do
      FileUtils.ln_s dir/"missing", link
      allow(Process).to receive(:euid).and_return(foreign_uid)

      expect(described_class.ownership_problem?(link, recursive: false)).to be true
    end

    it "is false when running as root" do
      FileUtils.touch file
      allow(Process).to receive(:euid).and_return(0)

      expect(described_class.ownership_problem?(file, recursive: false)).to be false
    end

    it "is false when the path does not exist" do
      allow(Process).to receive(:euid).and_return(foreign_uid)

      expect(described_class.ownership_problem?(file, recursive: false)).to be false
    end

    it "is false when the path does not exist and the check is recursive" do
      allow(Process).to receive(:euid).and_return(foreign_uid)

      expect(described_class.ownership_problem?(file, recursive: true)).to be false
    end

    it "is false when a subdirectory cannot be read" do
      path.mkpath
      FileUtils.chmod 0000, path.dirname

      expect(described_class.ownership_problem?(dir, recursive: true)).to be false
    ensure
      FileUtils.chmod 0755, path.dirname
    end
  end

  describe "::gain_permissions" do
    it "does not gain ownership when the current user already owns the path" do
      FileUtils.touch file
      allow(command).to receive(:run)
      expect(command).not_to receive(:run).with("chown", any_args)

      expect do
        described_class.gain_permissions(file, [], command) { raise Errno::EACCES, file.to_s }
      end.to raise_error(Errno::EACCES)
    end

    it "does not follow a symlink given with a trailing slash" do
      link.make_symlink(path.tap(&:mkpath))
      allow(command).to receive(:run)
      expect(command).to receive(:run).with("chmod", hash_including(args: ["-h", "--", "u+rwx", link]))

      expect do
        described_class.gain_permissions(Pathname("#{link}/"), ["-R"], command) { raise Errno::EACCES, link.to_s }
      end.to raise_error(Errno::EACCES)
    end
  end
end
