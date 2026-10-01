# typed: true
# frozen_string_literal: true

require "fileutils"

cc_shim = HOMEBREW_SHIMS_PATH/"super/cc"
cc_source = cc_shim.read
cc_ruby_offset = cc_source.index("#!/usr/bin/env ruby")
raise "no Ruby shebang found in #{cc_shim}" if cc_ruby_offset.nil?

module CcShim; end
CcShim.module_eval(cc_source[cc_ruby_offset..], cc_shim.to_s, cc_source[...cc_ruby_offset].count("\n") + 1)
CcShim::Cmd.include(CcShim)

RSpec.describe CcShim::Cmd do
  let(:root) { mktmpdir }
  let(:real_prefix) { "#{root}/real/brew" }
  let(:cellar) { "Cellar" }
  let(:opt) { "opt" }

  before do
    FileUtils.mkdir_p([
      "#{real_prefix}/include",
      "#{real_prefix}/lib/ocaml/caml",
      "#{real_prefix}/#{cellar}/ocaml/5.5.0/lib/ocaml",
      "#{real_prefix}/#{cellar}/undeclared/1.0/include",
      "#{real_prefix}/#{cellar}/testball/1.0/include",
      "#{real_prefix}/#{opt}",
      "#{root}/temp/build",
    ])
    FileUtils.ln_s("#{real_prefix}/#{cellar}/ocaml/5.5.0", "#{real_prefix}/#{opt}/ocaml")
    FileUtils.ln_s("#{real_prefix}/#{cellar}/undeclared/1.0", "#{real_prefix}/#{opt}/undeclared")
    FileUtils.ln_s("#{root}/real", "#{root}/link")
    FileUtils.ln_s(real_prefix, "#{root}/alias")
  end

  def setup_env(prefix)
    ENV["HOMEBREW_PREFIX"] = prefix
    ENV["HOMEBREW_CELLAR"] = "#{prefix}/#{cellar}"
    ENV["HOMEBREW_OPT"] = "#{prefix}/#{opt}"
    ENV["HOMEBREW_CACHE"] = "#{prefix}/cache"
    ENV["HOMEBREW_TEMP"] = "#{root}/temp"
    ENV["HOMEBREW_CCCFG"] = "O"
    ENV["HOMEBREW_OPTIMIZATION_LEVEL"] = "O2"
    ENV["HOMEBREW_DEPENDENCIES"] = "ocaml"
    ENV["HOMEBREW_FORMULA_PREFIX"] = "#{prefix}/#{cellar}/testball/1.0"
    ENV["HOMEBREW_OPTFLAGS"] = ""
    ENV["HOMEBREW_ISYSTEM_PATHS"] = "#{prefix}/include"
    ENV["HOMEBREW_INCLUDE_PATHS"] = ""
    ENV["HOMEBREW_LIBRARY_PATHS"] = "#{prefix}/lib"
    ENV["HOMEBREW_RPATH_PATHS"] = "#{prefix}/lib"
    ENV.delete("HOMEBREW_SDKROOT")
  end

  def include_flags(prefix)
    setup_env(prefix)

    argv = [
      "-c",
      "-I#{prefix}/include",
      "-I#{prefix}/lib/ocaml",
      "-I#{prefix}/#{opt}/ocaml/lib/ocaml",
      "-I#{prefix}/#{cellar}/testball/1.0/include",
      "-I#{root}/temp/build",
      "-I#{prefix}/#{cellar}/ocaml/5.5.0/lib/ocaml/notyet",
      "-I#{root}/alias/#{cellar}/ocaml/5.5.0/lib/ocaml/alsonotyet",
      "-I#{prefix}/#{opt}/undeclared/include",
      "-I#{prefix}/#{cellar}/undeclared/1.0/include",
      "test.c",
    ]

    described_class.new("gcc", argv).args.grep(/^-I/)
  end

  def link_flags(prefix)
    setup_env(prefix)

    argv = ["-o", "prog", "-L#{prefix}/#{cellar}/ocaml/5.5.0/lib", "prog.o"]

    described_class.new("gcc", argv).args
  end

  it "keeps build paths outside the sandbox temporary directory" do
    setup_env(real_prefix)
    buildpath = "#{root}/temp/build"
    ENV["HOMEBREW_FORMULA_BUILDPATH"] = buildpath
    ENV["HOMEBREW_TEMP"] = "#{root}/temp/sandbox"
    FileUtils.mkdir_p(["#{buildpath}/include", "#{buildpath}/lib", "#{root}/temp/sandbox"])

    Dir.chdir(buildpath) do
      command = described_class.new("gcc", ["-Iinclude", "-Llib", "test.c"])
      allow(command).to receive(:mac?).and_return(false)

      expect(command.args).to include("-Iinclude", "-Llib")
    end
  end

  it "keeps an explicit dependency -L ahead of its own library paths" do
    setup_env(real_prefix)
    ENV["HOMEBREW_LIBRARY_PATHS"] = "#{real_prefix}/lib:#{real_prefix}/#{opt}/ocaml/lib"

    argv = ["-o", "prog", "-L#{real_prefix}/#{opt}/ocaml/lib", "prog.o"]
    args = described_class.new("gcc", argv).args

    expect(args.index("-L#{real_prefix}/#{opt}/ocaml/lib")).to be < args.index("-L#{real_prefix}/lib")
  end

  it "drops an explicit -L for a library path it appends itself" do
    setup_env(real_prefix)
    ENV["HOMEBREW_LIBRARY_PATHS"] = "#{real_prefix}/#{cellar}/ocaml/5.5.0/lib:#{real_prefix}/lib"

    argv = ["-o", "prog", "-L#{real_prefix}/lib", "prog.o"]
    args = described_class.new("gcc", argv).args

    expect(args.count("-L#{real_prefix}/lib")).to eq(1)
  end

  it "targets x86_64 with Apple Clang under Rosetta 2" do
    setup_env(real_prefix)
    ENV["HOMEBREW_CC"] = "clang"
    ENV["HOMEBREW_OPTFLAGS"] = "-march=westmere"
    ENV["HOMEBREW_PROCESSOR"] = "Intel"
    ENV["HOMEBREW_PHYSICAL_PROCESSOR"] = "arm64"

    command = described_class.new("clang", ["-c", "test.c"])
    allow(command).to receive(:mac?).and_return(true)

    expect(command.args)
      .to include("-arch", "x86_64", "-march=westmere")
  end

  it "raises deployment targets below the minimum macOS version" do
    setup_env(real_prefix)
    ENV["HOMEBREW_MACOS_OLDEST_ALLOWED"] = "11"

    argv = [
      "-mmacosx-version-min=10.15",
      "-mmacosx-version-min=11",
      "-mmacosx-version-min=15.2",
    ]

    deployment_targets = described_class.new("clang", argv).args.grep(/^-mmacosx-version-min=/)
    expect(deployment_targets).to eq([
      "-mmacosx-version-min=11",
      "-mmacosx-version-min=11",
      "-mmacosx-version-min=15.2",
    ])
  end

  context "when no path component of the prefix is a symlink" do
    it "keeps the prefix, declared dependencies and references to self" do
      expect(include_flags(real_prefix)).to include(
        "-I#{real_prefix}/lib/ocaml",
        "-I#{real_prefix}/#{opt}/ocaml/lib/ocaml",
        "-I#{real_prefix}/#{cellar}/testball/1.0/include",
        "-I#{root}/temp/build",
      )
    end

    it "keeps directories that do not exist yet, however they are spelled" do
      expect(include_flags(real_prefix)).to include(
        "-I#{real_prefix}/#{cellar}/ocaml/5.5.0/lib/ocaml/notyet",
        "-I#{root}/alias/#{cellar}/ocaml/5.5.0/lib/ocaml/alsonotyet",
      )
    end

    it "drops paths superenv provides itself" do
      expect(include_flags(real_prefix)).not_to include("-I#{real_prefix}/include")
    end

    it "rejects undeclared dependencies" do
      expect(include_flags(real_prefix)).not_to include(
        "-I#{real_prefix}/#{opt}/undeclared/include",
        "-I#{real_prefix}/#{cellar}/undeclared/1.0/include",
      )
    end
  end

  context "when a path component of the prefix is a symlink" do
    let(:linked_prefix) { "#{root}/link/brew" }

    it "keeps the prefix, declared dependencies and references to self" do
      expect(include_flags(linked_prefix)).to include(
        "-I#{linked_prefix}/lib/ocaml",
        "-I#{linked_prefix}/#{opt}/ocaml/lib/ocaml",
        "-I#{linked_prefix}/#{cellar}/testball/1.0/include",
        "-I#{root}/temp/build",
      )
    end

    it "keeps directories that do not exist yet, however they are spelled" do
      expect(include_flags(linked_prefix)).to include(
        "-I#{linked_prefix}/#{cellar}/ocaml/5.5.0/lib/ocaml/notyet",
        "-I#{root}/alias/#{cellar}/ocaml/5.5.0/lib/ocaml/alsonotyet",
      )
    end

    it "drops paths superenv provides itself" do
      expect(include_flags(linked_prefix)).not_to include("-I#{linked_prefix}/include")
    end

    it "never emits a path with its symlinks resolved" do
      expect(link_flags(linked_prefix).join(" ")).not_to include("#{root}/real")
    end

    it "rejects undeclared dependencies" do
      expect(include_flags(linked_prefix)).not_to include(
        "-I#{linked_prefix}/#{opt}/undeclared/include",
        "-I#{linked_prefix}/#{cellar}/undeclared/1.0/include",
      )
    end
  end
end
