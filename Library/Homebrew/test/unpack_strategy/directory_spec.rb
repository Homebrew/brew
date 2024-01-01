# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Directory do
  subject(:strategy) { described_class.new(path) }

  let(:path) do
    mktmpdir.tap do |path|
      FileUtils.touch path/"file"
      FileUtils.ln_s "file", path/"symlink"
      FileUtils.mkdir path/"folder"
      FileUtils.ln_s "folder", path/"folderSymlink"
    end
  end

  let(:unpack_dir) { mktmpdir }

  it "does not follow symlinks" do
    strategy.extract(to: unpack_dir)
    expect(unpack_dir/"symlink").to be_a_symlink
  end

  it "does not follow top level symlinks to directories" do
    strategy.extract(to: unpack_dir)
    expect(unpack_dir/"folderSymlink").to be_a_symlink
  end

  it "preserves permissions of contained files" do
    FileUtils.chmod 0644, path/"file"

    strategy.extract(to: unpack_dir)
    expect((unpack_dir/"file").stat.mode & 0777).to eq 0644
  end

  it "preserves the permissions of the destination directory" do
    FileUtils.chmod 0700, path
    FileUtils.chmod 0755, unpack_dir

    strategy.extract(to: unpack_dir)
    expect(unpack_dir.stat.mode & 0777).to eq 0755
  end
end
