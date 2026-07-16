# typed: false
# frozen_string_literal: true

require "keg"

RSpec.describe Keg do
  subject(:keg) { described_class.new(keg_path) }

  include FileUtils

  describe "#mach_o_files" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }

    before { (keg_path/"lib").mkpath }

    after { keg.unlink }

    it "skips hardlinks" do
      cp dylib_path("i386"), keg_path/"lib/i386.dylib"
      ln keg_path/"lib/i386.dylib", keg_path/"lib/i386_hardlink.dylib"

      keg.link
      expect(keg.mach_o_files.count).to eq(1)
    end

    it "isn't confused by symlinks" do
      cp dylib_path("i386"), keg_path/"lib/i386.dylib"
      ln keg_path/"lib/i386.dylib", keg_path/"lib/i386_hardlink.dylib"
      ln_s keg_path/"lib/i386.dylib", keg_path/"lib/i386_symlink.dylib"

      keg.link
      expect(keg.mach_o_files.count).to eq(1)
    end
  end

  describe "#codesign_patched_binary" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:file) { "#{keg_path}/bin/test" }

    before do
      keg_path.mkpath
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("11"))
    end

    it "signs patched binaries using ruby-macho" do
      expect(keg).not_to receive(:system_command).with("codesign", any_args)
      expect(keg).not_to receive(:quiet_system).with("codesign", any_args)
      expect(MachO).to receive(:codesign!).with(file)

      keg.codesign_patched_binary(file)
    end
  end
end
