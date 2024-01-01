# frozen_string_literal: true

require "utils/pypi"

describe PyPI do
  let(:pypi_package_url) do
    "https://files.pythonhosted.org/packages/b0/3f/2e1dad67eb172b6443b5eb37eb885a054a55cfd733393071499514140282/" \
      "snakemake-5.29.0.tar.gz"
  end
  let(:old_pypi_package_url) do
    "https://files.pythonhosted.org/packages/6f/c4/da52bfdd6168ea46a0fe2b7c983b6c34c377a8733ec177cc00b197a96a9f/" \
      "snakemake-5.28.0.tar.gz"
  end
  let(:non_pypi_package_url) do
    "https://github.com/pypa/pip-audit/releases/download/v2.5.6/v2.5.6.tar.gz"
  end

  describe PyPI::Package do
    let(:package_checksum) { "47417307d08ecb0707b3b29effc933bd63d8c8e3ab15509c62b685b7614c6568" }
    let(:old_package_checksum) { "2367ce91baf7f8fa7738d33aff9670ffdf5410bbac49aeb209f73b45a3425046" }

    let(:package) { described_class.new("snakemake") }
    let(:package_with_version) { described_class.new("snakemake==5.28.0") }
    let(:package_with_different_version) { described_class.new("snakemake==5.29.0") }
    let(:package_with_extra) { described_class.new("snakemake[foo]") }
    let(:package_with_extra_and_version) { described_class.new("snakemake[foo]==5.28.0") }
    let(:package_with_different_capitalization) { described_class.new("SNAKEMAKE") }
    let(:package_from_pypi_url) { described_class.new(pypi_package_url, is_url: true) }
    let(:package_from_non_pypi_url) { described_class.new(non_pypi_package_url, is_url: true) }
    let(:other_package) { described_class.new("virtualenv==20.2.0") }

    describe "initialize" do
      it "initializes name" do
        expect(described_class.new("foo").name).to eq "foo"
      end

      it "initializes name with extra" do
        expect(described_class.new("foo[bar]").name).to eq "foo"
      end

      it "initializes extra" do
        expect(described_class.new("foo[bar]").extras).to eq ["bar"]
      end

      it "initializes multiple extras" do
        expect(described_class.new("foo[bar,baz]").extras).to eq ["bar", "baz"]
      end

      it "initializes name with version" do
        expect(described_class.new("foo==1.2.3").name).to eq "foo"
      end

      it "initializes version" do
        expect(described_class.new("foo==1.2.3").version).to eq "1.2.3"
      end

      it "initializes extra with version" do
        expect(described_class.new("foo[bar]==1.2.3").extras).to eq ["bar"]
      end

      it "initializes multiple extras with version" do
        expect(described_class.new("foo[bar,baz]==1.2.3").extras).to eq ["bar", "baz"]
      end

      it "initializes version with extra" do
        expect(described_class.new("foo[bar]==1.2.3").version).to eq "1.2.3"
      end

      it "initializes version with multiple extras" do
        expect(described_class.new("foo[bar,baz]==1.2.3").version).to eq "1.2.3"
      end

      it "initializes name from PyPI url" do
        expect(described_class.new(pypi_package_url, is_url: true).name).to eq "snakemake"
      end

      it "initializes version from PyPI url" do
        expect(described_class.new(pypi_package_url, is_url: true).version).to eq "5.29.0"
      end
    end

    describe ".version=" do
      it "sets for package names" do
        package = described_class.new("snakemake==5.28.0")
        expect(package.version).to eq "5.28.0"

        package.version = "5.29.0"
        expect(package.version).to eq "5.29.0"
      end

      it "sets for PyPI package URLs" do
        package = described_class.new(old_pypi_package_url, is_url: true)
        expect(package.version).to eq "5.28.0"

        package.version = "5.29.0"
        expect(package.version).to eq "5.29.0"
      end

      it "fails for non-PYPI package URLs" do
        package = described_class.new(non_pypi_package_url, is_url: true)

        expect { package.version = "1.2.3" }.to raise_error(ArgumentError)
      end
    end

    describe ".valid_pypi_package?" do
      it "is true for package names" do
        expect(package.valid_pypi_package?).to be true
      end

      it "is true for PyPI URLs" do
        expect(package_from_pypi_url.valid_pypi_package?).to be true
      end

      it "is false for non-PyPI URLs" do
        expect(package_from_non_pypi_url.valid_pypi_package?).to be false
      end
    end

    describe ".pypi_info", :needs_network do
      it "gets pypi info from a package name" do
        expect(package.pypi_info.first).to eq "snakemake"
      end

      it "gets pypi info from a package name and specified version" do
        expect(package.pypi_info(new_version: "5.29.0")).to eq ["snakemake", pypi_package_url, package_checksum,
                                                                "5.29.0"]
      end

      it "gets pypi info from a package name with extra" do
        expect(package_with_extra.pypi_info.first).to eq "snakemake"
      end

      it "gets pypi info from a package name and version" do
        expect(package_with_version.pypi_info).to eq ["snakemake", old_pypi_package_url, old_package_checksum,
                                                      "5.28.0"]
      end

      it "gets pypi info from a package name with overridden version" do
        expected_result = ["snakemake", pypi_package_url, package_checksum, "5.29.0"]
        expect(package_with_version.pypi_info(new_version: "5.29.0")).to eq expected_result
      end

      it "gets pypi info from a package name, extras, and version" do
        expected_result = ["snakemake", old_pypi_package_url, old_package_checksum, "5.28.0"]
        expect(package_with_extra_and_version.pypi_info).to eq expected_result
      end

      it "gets pypi info from a url" do
        expect(package_from_pypi_url.pypi_info).to eq ["snakemake", pypi_package_url, package_checksum, "5.29.0"]
      end

      it "gets pypi info from a url with overridden version" do
        expected_result = ["snakemake", old_pypi_package_url, old_package_checksum, "5.28.0"]
        expect(package_from_pypi_url.pypi_info(new_version: "5.28.0")).to eq expected_result
      end
    end

    describe ".to_s" do
      it "returns string representation of package name" do
        expect(package.to_s).to eq "snakemake"
      end

      it "returns string representation of package with version" do
        expect(package_with_version.to_s).to eq "snakemake==5.28.0"
      end

      it "returns string representation of package with extra" do
        expect(package_with_extra.to_s).to eq "snakemake[foo]"
      end

      it "returns string representation of package with extra and version" do
        expect(package_with_extra_and_version.to_s).to eq "snakemake[foo]==5.28.0"
      end

      it "returns string representation of package from url" do
        expect(package_from_pypi_url.to_s).to eq "snakemake==5.29.0"
      end
    end

    describe ".same_package?" do
      it "returns false for different packages" do
        expect(package.same_package?(other_package)).to be false
      end

      it "returns true for the same package" do
        expect(package.same_package?(package_with_version)).to be true
      end

      it "returns true for the same package with different versions" do
        expect(package_with_version.same_package?(package_with_different_version)).to be true
      end

      it "returns true for the same package with different capitalization" do
        expect(package.same_package?(package_with_different_capitalization)).to be true
      end
    end

    describe "<=>" do
      it "returns -1" do
        expect(package <=> other_package).to eq(-1)
      end

      it "returns 0" do
        expect(package <=> package_with_version).to eq 0
      end

      it "returns 1" do
        expect(other_package <=> package_with_extra_and_version).to eq 1
      end
    end
  end

  describe "update_pypi_url", :needs_network do
    it "updates url to new version" do
      expect(described_class.update_pypi_url(old_pypi_package_url, "5.29.0")).to eq pypi_package_url
    end

    it "returns nil for invalid versions" do
      expect(described_class.update_pypi_url(old_pypi_package_url, "0.0.0")).to be_nil
    end

    it "returns nil for non-pypi urls" do
      expect(described_class.update_pypi_url(non_pypi_package_url, "1.1")).to be_nil
    end
  end
end
