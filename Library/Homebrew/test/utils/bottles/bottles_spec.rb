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
end
