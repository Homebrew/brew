# typed: true
# frozen_string_literal: true

require "keg"
require "macho"

RSpec.describe Keg do
  subject(:keg) { described_class.new(keg_path) }

  let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }

  include FileUtils

  describe "#mach_o_files" do
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

  describe "::file_linked_libraries" do
    let(:file) { MachOPathname.wrap(keg_path/"lib/a.dylib") }

    before do
      file.dirname.mkpath
      touch file
      allow(MachOPathname).to receive(:wrap).and_return(file)
      allow(file).to receive_messages(dylib?: true, mach_o_executable?: false, mach_o_bundle?: false)
    end

    it "checks raw load-command names without resolving variable references" do
      expect(file).to receive(:dynamically_linked_libraries)
        .with(resolve_variable_references: false)
        .and_return(["@rpath/liba.dylib", "#{HOMEBREW_PREFIX}/lib/libb.dylib"])

      expect(described_class.file_linked_libraries(file, HOMEBREW_PREFIX.to_s))
        .to eq(["#{HOMEBREW_PREFIX}/lib/libb.dylib"])
    end
  end

  describe "#codesign_patched_binary" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:file) { "#{keg_path}/bin/test" }

    before do
      keg_path.mkpath
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("11"))
    end

    it "signs patched binaries using ruby-macho on Apple Silicon" do
      allow(Hardware::CPU).to receive(:arm?).and_return(true)
      expect(keg).not_to receive(:system_command).with("codesign", any_args)
      expect(keg).not_to receive(:quiet_system).with("codesign", any_args)
      expect(MachO).to receive(:codesign!).with(file)

      keg.codesign_patched_binary(file)
    end

    it "re-signs binaries whose signature has been broken using codesign on Intel" do
      allow(Hardware::CPU).to receive(:arm?).and_return(false)
      expect(MachO).not_to receive(:codesign!)
      expect(keg).to receive(:system_command)
        .with("codesign", args: ["--verify", file], print_stderr: false)
        .and_return(instance_double(SystemCommand::Result, stderr: "#{file}: invalid signature"))
      expect(keg).to receive(:quiet_system)
        .with("codesign", "--sign", "-", "--force",
              "--preserve-metadata=entitlements,requirements,flags,runtime", file)
        .and_return(true)

      keg.codesign_patched_binary(file)
    end

    it "does not sign unsigned binaries on Intel" do
      allow(Hardware::CPU).to receive(:arm?).and_return(false)
      expect(MachO).not_to receive(:codesign!)
      expect(keg).to receive(:system_command)
        .with("codesign", args: ["--verify", file], print_stderr: false)
        .and_return(instance_double(SystemCommand::Result, stderr: "#{file}: code object is not signed at all"))
      expect(keg).not_to receive(:quiet_system).with("codesign", any_args)

      keg.codesign_patched_binary(file)
    end
  end

  describe "#relocate_dynamic_linkage" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:file) { MachOPathname.wrap(keg_path/"bin/test") }
    let(:relocation) do
      relocation = Keg::Relocation.new
      relocation.add_replacement_pair(:prefix, HOMEBREW_PREFIX.to_s, Keg::PREFIX_PLACEHOLDER)
      relocation.add_replacement_pair(:cellar, HOMEBREW_CELLAR.to_s, Keg::CELLAR_PLACEHOLDER)
      relocation
    end

    before do
      file.dirname.mkpath
      touch file
      allow(file).to receive(:ensure_writable).and_yield
      allow(file).to receive(:save_changes)
      allow(file).to receive_messages(dylib?: false, dynamically_linked_libraries: ["#{HOMEBREW_PREFIX}/lib/foo"],
                                      rpaths: [])
      allow(keg).to receive_messages(mach_o_files: [file], change_install_name: true)
      allow(keg).to receive(:codesign_patched_binaries)
    end

    after { keg.unlink }

    it "returns changed linkage files relative to the keg" do
      expect(keg.relocate_dynamic_linkage(relocation)).to eq([Pathname("bin/test")])
    end

    it "saves each changed file once and codesigns changed files together" do
      expect(file).to receive(:save_changes).once
      expect(keg).to receive(:codesign_patched_binaries).with([keg_path/"bin/test"])

      keg.relocate_dynamic_linkage(relocation)
    end

    it "relocates only recorded linkage files without walking the keg" do
      allow(MachOPathname).to receive(:wrap).and_return(file)
      expect(keg).not_to receive(:mach_o_files)

      expect(keg.relocate_dynamic_linkage(relocation, files: [Pathname("bin/test")])).to eq([Pathname("bin/test")])
    end
  end

  describe "#fix_dynamic_linkage" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:file) { MachOPathname.wrap(keg_path/"bin/test") }

    before do
      file.dirname.mkpath
      touch file
      allow(file).to receive(:ensure_writable).and_yield
      allow(file).to receive(:save_changes)
      allow(file).to receive_messages(dylib?: false, rpaths: [],
                                      dynamically_linked_libraries: ["#{Keg::PREFIX_PLACEHOLDER}/lib/foo"])
      allow(keg).to receive_messages(mach_o_files: [file], change_install_name: true)
      allow(keg).to receive(:codesign_patched_binaries)
    end

    after { keg.unlink }

    it "saves each fixed file once and codesigns fixed files together" do
      expect(file).to receive(:save_changes).once
      expect(keg).to receive(:codesign_patched_binaries).with([file])

      keg.fix_dynamic_linkage
    end
  end

  describe "#relocate_build_prefix" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:file) { keg_path/"lib/libfoo.dylib" }

    before do
      file.dirname.mkpath
      cp dylib_path("x86_64"), file
      MachOPathname.wrap(file).change_install_name("/usr/lib/libSystem.B.dylib", "/old/pfx/libSys.B.dylib")
      allow(keg).to receive(:codesign_patched_binaries)
    end

    after { keg.unlink }

    it "patches prefix strings inside load commands" do
      keg.relocate_build_prefix(keg, "/old/pfx", "/new", files: [Pathname("lib/libfoo.dylib")])

      expect(MachOPathname.wrap(file).dynamically_linked_libraries(resolve_variable_references: false))
        .to eq ["/new/libSys.B.dylib"]
    end
  end

  describe "#codesign_patched_binaries" do
    let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
    let(:files) { [keg_path/"bin/a", keg_path/"bin/b"] }

    before do
      (keg_path/"bin").mkpath
      files.each { |file| touch file }
    end

    after { keg.unlink }

    it "codesigns every file" do
      files.each { |file| expect(keg).to receive(:codesign_patched_binary).with(file.to_s) }

      keg.codesign_patched_binaries(files)
    end
  end
end
