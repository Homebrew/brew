# frozen_string_literal: true

require "compilers"
require "software_spec"

describe CompilerSelector do
  subject(:selector) { described_class.new(software_spec, versions, compilers) }

  let(:compilers) { [:clang, :gnu] }
  let(:software_spec) { SoftwareSpec.new }
  let(:cc) { :clang }
  let(:versions) { class_double(DevelopmentTools, clang_build_version: Version.new("600")) }

  before do
    allow(versions).to receive(:gcc_version) do |name|
      case name
      when "gcc-7" then Version.new("7.1")
      when "gcc-6" then Version.new("6.1")
      when "gcc-5" then Version.new("5.1")
      when "gcc-4.9" then Version.new("4.9.1")
      else Version::NULL
      end
    end
  end

  describe "#compiler" do
    it "defaults to cc" do
      expect(selector.compiler).to eq(cc)
    end

    it "returns clang if it fails with non-Apple gcc" do
      software_spec.fails_with(gcc: "7")
      expect(selector.compiler).to eq(:clang)
    end

    it "still returns gcc-7 if it fails with gcc without a specific version" do
      software_spec.fails_with(:clang)
      expect(selector.compiler).to eq("gcc-7")
    end

    it "returns gcc-6 if gcc formula offers gcc-6 on mac", :needs_macos do
      software_spec.fails_with(:clang)
      allow(Formulary).to receive(:factory)
        .with("gcc")
        .and_return(instance_double(Formula, version: Version.new("6.0")))
      expect(selector.compiler).to eq("gcc-6")
    end

    it "returns gcc-5 if gcc formula offers gcc-5 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      allow(Formulary).to receive(:factory)
        .with("gcc@11")
        .and_return(instance_double(Formula, version: Version.new("5.0")))
      expect(selector.compiler).to eq("gcc-5")
    end

    it "returns gcc-6 if gcc formula offers gcc-5 and fails with gcc-5 and gcc-7 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "5")
      software_spec.fails_with(gcc: "7")
      allow(Formulary).to receive(:factory)
        .with("gcc@11")
        .and_return(instance_double(Formula, version: Version.new("5.0")))
      expect(selector.compiler).to eq("gcc-6")
    end

    it "returns gcc-7 if gcc formula offers gcc-5 and fails with gcc <= 6 on linux", :needs_linux do
      software_spec.fails_with(:clang)
      software_spec.fails_with(:gcc) { version "6" }
      allow(Formulary).to receive(:factory)
        .with("gcc@11")
        .and_return(instance_double(Formula, version: Version.new("5.0")))
      expect(selector.compiler).to eq("gcc-7")
    end

    it "returns gcc-7 if gcc-7 is version 7.1 but spec fails with gcc-7 <= 7.0" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "7") { version "7.0" }
      expect(selector.compiler).to eq("gcc-7")
    end

    it "returns gcc-6 if gcc-7 is version 7.1 but spec fails with gcc-7 <= 7.1" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "7") { version "7.1" }
      expect(selector.compiler).to eq("gcc-6")
    end

    it "raises an error when gcc or llvm is missing (hash syntax)" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(gcc: "7")
      software_spec.fails_with(gcc: "6")
      software_spec.fails_with(gcc: "5")
      software_spec.fails_with(gcc: "4.9")

      expect { selector.compiler }.to raise_error(CompilerSelectionError)
    end

    it "raises an error when gcc or llvm is missing (symbol syntax)" do
      software_spec.fails_with(:clang)
      software_spec.fails_with(:gcc)

      expect { selector.compiler }.to raise_error(CompilerSelectionError)
    end
  end
end
