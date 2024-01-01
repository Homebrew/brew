# frozen_string_literal: true

require "keg"

describe Keg do
  include FileUtils

  subject(:keg) { described_class.new(keg_path) }

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
end
