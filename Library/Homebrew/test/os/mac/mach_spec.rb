# frozen_string_literal: true

RSpec.describe MachOShim do
  describe "Pathname tests" do
    specify "fat dylib" do
      pn = dylib_path("fat")
      expect(pn).to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn.arch).to eq(:universal)
    end

    specify "i386 dylib" do
      pn = dylib_path("i386")
      expect(pn).not_to be_universal
      expect(pn).to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).not_to be_mach_o_bundle
    end

    specify "x86_64 dylib" do
      pn = dylib_path("x86_64")
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).not_to be_mach_o_bundle
    end

    specify "Mach-O executable" do
      pn = Pathname.new("#{TEST_FIXTURE_DIR}/mach/a.out")
      expect(pn).to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).not_to be_mach_o_bundle
    end

    specify "fat bundle" do
      pn = bundle_path("fat")
      expect(pn).to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).to be_mach_o_bundle
    end

    specify "i386 bundle" do
      pn = bundle_path("i386")
      expect(pn).not_to be_universal
      expect(pn).to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).to be_mach_o_bundle
    end

    specify "x86_64 bundle" do
      pn = bundle_path("x86_64")
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).to be_mach_o_bundle
    end

    specify "non-Mach-O" do
      pn = Pathname.new("#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz")
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn).not_to be_mach_o_bundle
      expect(pn.arch).to eq(:dunno)
    end
  end

  describe "text executables" do
    let(:pn) { HOMEBREW_PREFIX/"an_executable" }

    after { pn.unlink }

    specify "simple shebang" do
      pn.write "#!/bin/sh"
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).to be_text_executable
      expect(pn.archs).to eq([])
      expect(pn.arch).to eq(:dunno)
    end

    specify "shebang with options" do
      pn.write "#! /usr/bin/perl -w"
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).to be_text_executable
      expect(pn.archs).to eq([])
      expect(pn.arch).to eq(:dunno)
    end

    specify "malformed shebang" do
      pn.write " #!"
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(pn).not_to be_text_executable
      expect(pn.archs).to eq([])
      expect(pn.arch).to eq(:dunno)
    end
  end
end
