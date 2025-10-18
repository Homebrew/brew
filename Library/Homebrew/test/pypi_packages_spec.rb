# frozen_string_literal: true

require "pypi_packages"

RSpec.describe PypiPackages do
  describe ".from_json_file" do
    let(:tap) { Tap.fetch("homebrew", "foo") }
    let(:formula_name) { "test-formula" }
    let(:mappings) { nil }

    before do
      allow(tap).to receive(:pypi_formula_mappings).and_return(mappings)
    end

    context "when JSON is `nil`" do
      it "returns an instance with defined_pypi_mapping: false" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs).to be_a(described_class)
        expect(pkgs.defined_pypi_mapping?).to be(false)
        expect(pkgs.needs_manual_update?).to be(false)
        expect(pkgs.package_name).to be_nil
      end
    end

    context "when JSON is an empty hash" do
      let(:mappings) { {} }

      it "returns an instance with defined_pypi_mapping: false" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs).to be_a(described_class)
        expect(pkgs.defined_pypi_mapping?).to be(false)
        expect(pkgs.needs_manual_update?).to be(false)
        expect(pkgs.package_name).to be_nil
      end
    end

    context "when mapping entry is `false`" do
      let(:mappings) { { formula_name => false } }

      it "returns an instance with needs_manual_update: true" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs).to be_a(described_class)
        expect(pkgs.defined_pypi_mapping?).to be(true)
        expect(pkgs.needs_manual_update?).to be(true)
        expect(pkgs.package_name).to be_nil
      end
    end

    context "when mapping entry is a String" do
      let(:mappings) { { formula_name => "bar" } }

      it "returns an instance with package_name set" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs.package_name).to eq("bar")
        expect(pkgs.extra_packages).to eq([])
        expect(pkgs.exclude_packages).to eq([])
        expect(pkgs.dependencies).to eq([])
        expect(pkgs.defined_pypi_mapping?).to be(true)
        expect(pkgs.needs_manual_update?).to be(false)
      end
    end

    context "when mapping entry is `true`" do
      let(:mappings) { { formula_name => true } }

      it "raises a Sorbet type error" do
        expect do
          described_class.from_json_file(tap, formula_name)
        end.to raise_error(TypeError, /got type TrueClass/)
      end
    end

    context "when mapping entry is a Hash" do
      let(:mappings) do
        {
          formula_name => {
            "package_name"     => "bar",
            "extra_packages"   => ["baz"],
            "exclude_packages" => ["qux"],
            "dependencies"     => ["quux"],
          },
        }
      end

      it "returns an instance with all fields populated" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs.package_name).to eq("bar")
        expect(pkgs.extra_packages).to eq(["baz"])
        expect(pkgs.exclude_packages).to eq(["qux"])
        expect(pkgs.dependencies).to eq(["quux"])
        expect(pkgs.defined_pypi_mapping?).to be(true)
        expect(pkgs.needs_manual_update?).to be(false)
      end
    end

    context "when mapping entry hash omits optional keys" do
      let(:mappings) do
        { formula_name => { "package_name" => "bar" } }
      end

      it "fills missing keys with empty arrays" do
        pkgs = described_class.from_json_file(tap, formula_name)
        expect(pkgs.package_name).to eq("bar")
        expect(pkgs.extra_packages).to eq([])
        expect(pkgs.exclude_packages).to eq([])
        expect(pkgs.dependencies).to eq([])
      end
    end

    context "when mapping entry hash uses Array for `package_name`" do
      let(:mappings) do
        { formula_name => { "package_name" => ["bar"] } }
      end

      it "raises a Sorbet type error" do
        expect do
          described_class.from_json_file(tap, formula_name)
        end.to raise_error(TypeError, /got type Array/)
      end
    end

    context "when mapping entry hash uses String for keys" do
      let(:mappings) do
        { formula_name => { "extra_packages" => "bar" } }
      end

      it "raises a Sorbet type error" do
        expect do
          described_class.from_json_file(tap, formula_name)
        end.to raise_error(TypeError, /got type String/)
      end
    end

    context "when tap is `nil`" do
      it "fills missing keys with empty arrays" do
        pkgs = described_class.from_json_file(nil, formula_name)
        expect(pkgs.defined_pypi_mapping?).to be(false)
        expect(pkgs.package_name).to be_nil
      end
    end
  end
end
