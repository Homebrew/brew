# typed: strict
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

  describe ".extname_tag_rebuild" do
    it "returns an empty rebuild for bottles without rebuilds" do
      expect(described_class.extname_tag_rebuild("gh--2.93.0.arm64_sonoma.bottle.tar.gz"))
        .to eq([".arm64_sonoma.bottle.tar.gz", "arm64_sonoma", ""])
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
      end

      it "includes runtime_dependencies" do
        formula = Formula["testball2"]
        formula.prefix.mkpath

        runtime_dependencies = described_class.load_tab(formula).runtime_dependencies

        expect(runtime_dependencies).to contain_exactly(a_hash_including("full_name" => "testball1"))
      end
    end

    # The `sh.brew.tab` manifest annotation is fetched without a checksum, so the build prefix
    # must be derived from trusted sources rather than taken from the annotation.
    context "when the manifest annotation supplies a built_prefix" do
      before do
        path = CoreTap.instance.new_formula_path("testball1")
        path.write <<~RUBY
          class #{Formulary.class_s("testball1")} < Formula
            url "testball1"
            version "0.1"
          end
        RUBY
        Formula["testball1"].prefix.mkpath
        # An arm64 macOS tag has a padded prefix on every host, unlike the running tag.
        allow(described_class).to receive(:tag)
          .and_return(Utils::Bottles::Tag.new(system: :tahoe, arch: :arm64))
      end

      it "derives a pinned-cellar prefix from the formula rather than the annotation" do
        formula = Formula["testball1"]
        allow(formula.bottle_specification).to receive(:tag_to_cellar).and_return("/custom/prefix/Cellar")
        allow(formula).to receive(:bottle_tab_attributes).and_return(
          "built_on" => { "os" => HOMEBREW_SYSTEM }, "built_prefix" => "/usr", "padded_prefix" => false,
        )

        expect(described_class.load_tab(formula).built_prefix).to eq("/custom/prefix")
      end

      it "clears the prefix for a relocatable bottle" do
        formula = Formula["testball1"]
        allow(formula.bottle_specification).to receive(:tag_to_cellar).and_return(:any_skip_relocation)
        allow(formula).to receive(:bottle_tab_attributes).and_return(
          "built_on" => { "os" => HOMEBREW_SYSTEM }, "built_prefix" => "/usr", "padded_prefix" => false,
        )

        expect(described_class.load_tab(formula).built_prefix).to be_nil
      end

      it "substitutes this tag's padded prefix for a padded bottle" do
        formula = Formula["testball1"]
        padded = Utils::Bottles::Tag.new(system: :tahoe, arch: :arm64).padded_prefix
        allow(formula).to receive(:bottle_tab_attributes).and_return(
          "built_on" => { "os" => HOMEBREW_SYSTEM }, "built_prefix" => padded, "padded_prefix" => true,
        )

        expect(described_class.load_tab(formula).built_prefix).to eq(padded)
      end

      it "substitutes the local prefix even when a padded bottle supplies a forged one" do
        formula = Formula["testball1"]
        padded = Utils::Bottles::Tag.new(system: :tahoe, arch: :arm64).padded_prefix
        allow(formula).to receive(:bottle_tab_attributes).and_return(
          "built_on" => { "os" => HOMEBREW_SYSTEM }, "built_prefix" => "/usr", "padded_prefix" => true,
        )

        expect(described_class.load_tab(formula).built_prefix).to eq(padded)
      end
    end
  end
end
