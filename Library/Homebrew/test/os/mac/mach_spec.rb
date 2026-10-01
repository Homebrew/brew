# typed: true
# frozen_string_literal: true

RSpec.describe MachOShim do
  specify "Sorbet runtime loads MachO before Pathname initialisation", :integration_test do
    ruby = <<~RUBY
      ENV.delete("HOMEBREW_SORBET_RUNTIME")

      require "os/mac/mach"
      Pathname.prepend(MachOShim)
      Pathname.new("test")

      abort "MachO is not defined" unless Object.const_defined?(:MachO)
    RUBY

    _, stderr, status = Open3.capture3(
      { "HOMEBREW_SORBET_RUNTIME" => "1" },
      *HOMEBREW_RUBY_EXEC_ARGS,
      "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
      "-rpathname", "-rstandalone/sorbet", "-e", ruby
    )

    expect(status).to be_success, stderr
  end

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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
      expect(pn).not_to be_mach_o_bundle
    end

    specify "Mach-O executable" do
      pn = MachOPathname.wrap("#{TEST_FIXTURE_DIR}/mach/a.out")
      expect(pn).to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).to be_mach_o_executable
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
      expect(pn).to be_mach_o_bundle
    end

    specify "non-Mach-O" do
      pn = MachOPathname.wrap("#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz")
      expect(pn).not_to be_universal
      expect(pn).not_to be_i386
      expect(pn).not_to be_x86_64
      expect(pn).not_to be_ppc7400
      expect(pn).not_to be_ppc64
      expect(pn).not_to be_dylib
      expect(pn).not_to be_mach_o_executable
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
      expect(pn).not_to be_mach_o_bundle
      expect(pn.arch).to eq(:dunno)
    end
  end

  describe "#delete_rpath" do
    specify "returns nil without rewriting the binary when no rpath matches" do
      pn = dylib_path("x86_64")
      contents = pn.read
      expect(pn.delete_rpath("/nonexistent", strict: false)).to be_nil
      expect(pn.read).to eq(contents)
    end
  end

  describe "text executables" do
    let(:pn) { MachOPathname.wrap(HOMEBREW_PREFIX/"an_executable") }

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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(true)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(true)
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
      expect(Utils::Path.text_executable?(Pathname(pn.to_path))).to be(false)
      expect(pn.archs).to eq([])
      expect(pn.arch).to eq(:dunno)
    end
  end
end
