# typed: true
# frozen_string_literal: true

require "compilers"
require "software_spec"

RSpec.describe CompilerSelector do
  subject(:selector) { described_class.new(software_spec, versions, compilers) }

  let(:compilers) { [:clang, :gnu] }
  let(:software_spec) { SoftwareSpec.new }
  let(:cc) { :clang }
  let(:versions) { class_double(DevelopmentTools, clang_build_version: Version.new("600")) }

  before do
    allow(versions).to receive(:gcc_version) do |name|
      case name
      when "gcc-12" then Version.new("12.1")
      when "gcc-11" then Version.new("11.1")
      when "gcc-10" then Version.new("10.1")
      when "gcc-9" then Version.new("9.1")
      else Version::NULL
      end
    end
  end

  describe "#compiler", :no_api do
    it "defaults to cc" do
      expect(selector.compiler).to eq(cc)
    end

    it "returns clang if it fails with non-Apple gcc" do
      software_spec.fails_with(gcc: "12")
      expect(selector.compiler).to eq(:clang)
    end

    it "still returns gcc-12 if it fails with gcc without a specific version" do
      software_spec.fails_with(:clang)
      expect(selector.compiler).to eq("gcc-12")
    end

    it "returns gcc-11 if gcc formula offers gcc-11 on mac", :needs_macos do
      software_spec.fails_with(:clang)
      allow(Formulary).to receive(:factory)
        .with("gcc")
        .and_return(instance_double(Formula, version: Version.new("11.0")))
      expect(selector.compiler).to eq("gcc-11")
    end

    it "returns gcc-10 if gcc formula offers gcc-10 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      allow(Formulary).to receive(:factory)
        .with(OS::LINUX_PREFERRED_GCC_COMPILER_FORMULA)
        .and_return(instance_double(Formula, version: Version.new("10.0")))
      expect(selector.compiler).to eq("gcc-10")
    end

    it "returns gcc-11 if gcc formula offers gcc-10 and fails with gcc-10 and gcc-12 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "10")
      software_spec.fails_with(gcc: "12")
      allow(Formulary).to receive(:factory)
        .with(OS::LINUX_PREFERRED_GCC_COMPILER_FORMULA)
        .and_return(instance_double(Formula, version: Version.new("10.0")))
      expect(selector.compiler).to eq("gcc-11")
    end

    it "returns gcc-12 if gcc formula offers gcc-11 and fails with gcc <= 11 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      software_spec.fails_with(:gcc) do
        T.bind(self, CompilerFailure)
        version "11"
      end
      allow(Formulary).to receive(:factory)
        .with(OS::LINUX_PREFERRED_GCC_COMPILER_FORMULA)
        .and_return(instance_double(Formula, version: Version.new("11.0")))
      expect(selector.compiler).to eq("gcc-12")
    end

    it "returns gcc-12 if gcc-12 is version 12.1 but spec fails with gcc-12 <= 12.0" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "12") do
        T.bind(self, CompilerFailure)
        version "12.0"
      end
      expect(selector.compiler).to eq("gcc-12")
    end

    it "returns gcc-11 if gcc-12 is version 12.1 but spec fails with gcc-12 <= 12.1" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "12") do
        T.bind(self, CompilerFailure)
        version "12.1"
      end
      expect(selector.compiler).to eq("gcc-11")
    end

    it "raises an error when gcc or llvm is missing (hash syntax)" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "12")
      software_spec.fails_with(gcc: "11")
      software_spec.fails_with(gcc: "10")
      software_spec.fails_with(gcc: "9")

      expect { selector.compiler }.to raise_error(CompilerSelectionError)
    end

    it "raises an error when gcc or llvm is missing (symbol syntax)" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(:gcc)

      expect { selector.compiler }.to raise_error(CompilerSelectionError)
    end

    context "when selecting LLVM Clang" do
      let(:compilers) { [:llvm_clang, :clang] }
      let(:versions) { Class.new(DevelopmentTools) }

      before do
        allow(versions).to receive(:clang_build_version).and_return(Version.new("600"))
      end

      it "selects LLVM Clang without calling deprecated APIs" do
        llvm_prefix = mktmpdir
        clang = llvm_prefix/"bin/clang"
        clang.dirname.mkpath
        clang.write "#!/bin/sh\n"
        clang.chmod 0755

        allow(Formula).to receive(:[]).with("llvm")
                                      .and_return(instance_double(Formula, opt_prefix: llvm_prefix))
        allow(Utils).to receive(:popen_read_text)
          .with(clang, "--version", err: :err).and_return("clang version 21.1.0\n")

        expect(selector.compiler).to eq(:llvm_clang)
      end

      it "falls back to Clang without calling deprecated APIs when LLVM is unavailable" do
        allow(Formula).to receive(:[]).with("llvm").and_raise(FormulaUnavailableError.new("llvm"))

        expect(selector.compiler).to eq(:clang)
      end
    end
  end
end
