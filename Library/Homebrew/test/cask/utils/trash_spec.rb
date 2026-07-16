# typed: false
# frozen_string_literal: true

require "cask/utils/trash"

RSpec.describe Cask::Utils::Trash do
  describe "::trash", :needs_macos do
    let(:path) { Pathname("/tmp/example") }
    let(:trashed_path) { "/Users/example/.Trash/example" }

    it "uses the Foundation trash implementation by default" do
      expect(MacOS::FFI::Foundation).to receive(:trash_paths)
        .with([path.to_s])
        .and_return([[trashed_path], []])

      with_env(HOMEBREW_DEVELOPER: nil) do
        expect(described_class.trash(path)).to eq([[trashed_path], []])
      end
    end

    it "retries untrashable paths after gaining permissions" do
      expect(MacOS::FFI::Foundation).to receive(:trash_paths)
        .with([path.to_s])
        .and_return([[], [path.to_s]])
      expect(Cask::Utils).to receive(:gain_permissions)
        .with(path, ["-R"], SystemCommand)
        .and_yield
      expect(MacOS::FFI::Foundation).to receive(:trash_item)
        .with(path.to_s)
        .and_return(trashed_path)

      with_env(HOMEBREW_DEVELOPER: nil) do
        expect(described_class.trash(path)).to eq([[trashed_path], []])
      end
    end
  end

  describe "::freedesktop_trash" do
    let(:deletion_time) { Time.local(2026, 4, 25, 13, 14, 15) }
    let(:xdg_data_home) { mktmpdir/"xdg-data" }
    let(:trash_path) { xdg_data_home/"Trash" }
    let(:files_path) { trash_path/"files" }
    let(:info_path) { trash_path/"info" }
    let(:path) { mktmpdir/"folder with spaces"/"example file.txt" }

    around do |example|
      old_xdg_data_home = ENV.fetch("XDG_DATA_HOME", nil)
      ENV["XDG_DATA_HOME"] = xdg_data_home.to_s
      example.run
    ensure
      ENV["XDG_DATA_HOME"] = old_xdg_data_home
    end

    it "moves files into the XDG trash and writes a trashinfo file" do
      path.dirname.mkpath
      path.write("example")
      allow(Time).to receive(:now).and_return(deletion_time)

      trashed, untrashable = described_class.freedesktop_trash(path)

      expect(path).not_to exist
      expect(trashed).to eq([path.to_s])
      expect(untrashable).to be_empty
      expect((files_path/"example file.txt").read).to eq("example")
      expect((info_path/"example file.txt.trashinfo").read).to eq(<<~EOS)
        [Trash Info]
        Path=#{URI::DEFAULT_PARSER.escape(path.to_s)}
        DeletionDate=2026-04-25T13:14:15
      EOS
    end
  end
end
