# frozen_string_literal: true

require "utils/bottles"

RSpec.describe Utils::Bottles do
  describe "#tag", :needs_macos do
    it "returns :big_sur or :arm64_big_sur on Big Sur" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("11.0"))
      if Hardware::CPU.intel?
        expect(described_class.tag).to eq(:big_sur)
      else
        expect(described_class.tag).to eq(:arm64_big_sur)
      end
    end
  end

  describe ".load_tab" do
    context "when tab_attributes and tabfile are missing" do
      before do
        # setup a testball1
        dep_name = "testball1"
        dep_path = CoreTap.instance.new_formula_path(dep_name)
        dep_path.write <<~RUBY
          class #{Formulary.class_s(dep_name)} < Formula
            url "testball1"
            version "0.1"
          end
        RUBY
        Formulary.cache.delete(dep_path)

        # setup a testball2, that depends on testball1
        formula_name = "testball2"
        formula_path = CoreTap.instance.new_formula_path(formula_name)
        formula_path.write <<~RUBY
          class #{Formulary.class_s(formula_name)} < Formula
            url "testball2"
            version "0.1"
            depends_on "testball1"
          end
        RUBY
        Formulary.cache.delete(formula_path)
      end

      it "includes runtime_dependencies" do
        formula = Formula["testball2"]
        formula.prefix.mkpath

        runtime_dependencies = described_class.load_tab(formula).runtime_dependencies

        expect(runtime_dependencies).not_to be_nil
        expect(runtime_dependencies.size).to eq(1)
        expect(runtime_dependencies.first).to include("full_name" => "testball1")
      end
    end
  end

  describe "#skip_relocation_for_apple_silicon?" do
    let(:keg) { double("keg") }

    before do
      allow(keg).to receive(:mach_o_files).and_return([])
    end

    it "returns true for Apple Silicon with default prefix when enabled by env var" do
      allow(Hardware::CPU).to receive(:arm?).and_return(true)
      allow(OS).to receive(:mac?).and_return(true)
      allow(HOMEBREW_PREFIX).to receive(:to_s).and_return(HOMEBREW_MACOS_ARM_DEFAULT_PREFIX)
      allow(ENV).to receive(:fetch).with("HOMEBREW_BOTTLE_SKIP_RELOCATION_ARM64", "false").and_return("true")

      expect(described_class.skip_relocation_for_apple_silicon?).to be true
    end

    it "returns true for Apple Silicon with default prefix when no binaries need relocation" do
      allow(Hardware::CPU).to receive(:arm?).and_return(true)
      allow(OS).to receive(:mac?).and_return(true)
      allow(HOMEBREW_PREFIX).to receive(:to_s).and_return(HOMEBREW_MACOS_ARM_DEFAULT_PREFIX)
      allow(ENV).to receive(:fetch).with("HOMEBREW_BOTTLE_SKIP_RELOCATION_ARM64", "false").and_return("false")

      expect(described_class.skip_relocation_for_apple_silicon?(keg)).to be true
    end

    it "returns false for Apple Silicon with default prefix when binaries need relocation" do
      mach_o_file = double("mach_o_file")
      allow(keg).to receive(:mach_o_files).and_return([mach_o_file])
      allow(mach_o_file).to receive(:dylib?).and_return(true)
      allow(mach_o_file).to receive(:dylib_id).and_return("/usr/local/lib/example.dylib")

      allow(Hardware::CPU).to receive(:arm?).and_return(true)
      allow(OS).to receive(:mac?).and_return(true)
      allow(HOMEBREW_PREFIX).to receive(:to_s).and_return(HOMEBREW_MACOS_ARM_DEFAULT_PREFIX)
      allow(ENV).to receive(:fetch).with("HOMEBREW_BOTTLE_SKIP_RELOCATION_ARM64", "false").and_return("false")

      expect(described_class.skip_relocation_for_apple_silicon?(keg)).to be false
    end

    it "returns false for Intel Mac" do
      allow(Hardware::CPU).to receive(:arm?).and_return(false)
      allow(OS).to receive(:mac?).and_return(true)

      expect(described_class.skip_relocation_for_apple_silicon?).to be false
      expect(described_class.skip_relocation_for_apple_silicon?(keg)).to be false
    end

    it "returns false for custom prefix on Apple Silicon" do
      allow(Hardware::CPU).to receive(:arm?).and_return(true)
      allow(OS).to receive(:mac?).and_return(true)
      allow(HOMEBREW_PREFIX).to receive(:to_s).and_return("/custom/path")

      expect(described_class.skip_relocation_for_apple_silicon?).to be false
      expect(described_class.skip_relocation_for_apple_silicon?(keg)).to be false
    end
  end

  describe "#binaries_need_relocation?" do
    let(:keg) { instance_double("Keg") }
    let(:mach_o_file) { instance_double("MachO::MachOFile") }

    it "returns true when dylib has /usr/local path" do
      allow(OS).to receive(:mac?).and_return(true)
      allow(keg).to receive(:mach_o_files).and_return([mach_o_file])
      allow(mach_o_file).to receive_messages(
        dylib?: true,
        dylib_id: "/usr/local/lib/example.dylib"
      )
      allow(mach_o_file).to receive(:dynamically_linked_libraries).and_return([])

      expect(described_class.binaries_need_relocation?(keg)).to be true
    end

    it "returns true when linked libraries have /usr/local path" do
      allow(OS).to receive(:mac?).and_return(true)
      allow(keg).to receive(:mach_o_files).and_return([mach_o_file])
      allow(mach_o_file).to receive(:dylib?).and_return(false)
      allow(mach_o_file).to receive(:dynamically_linked_libraries).and_return(["/usr/local/lib/libexample.dylib"])

      expect(described_class.binaries_need_relocation?(keg)).to be true
    end

    it "returns false when no paths need relocation" do
      allow(OS).to receive(:mac?).and_return(true)
      allow(keg).to receive(:mach_o_files).and_return([mach_o_file])
      allow(mach_o_file).to receive(:dylib?).and_return(true)
      allow(mach_o_file).to receive(:dylib_id).and_return("/opt/homebrew/lib/libexample.dylib")
      allow(mach_o_file).to receive(:dynamically_linked_libraries).and_return(["/opt/homebrew/lib/libother.dylib"])

      expect(described_class.binaries_need_relocation?(keg)).to be false
    end
  end
end
