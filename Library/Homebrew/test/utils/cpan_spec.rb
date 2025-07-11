# frozen_string_literal: true

require "utils/cpan"

RSpec.describe CPAN do
  let(:cpan_package_url) do
    "https://cpan.metacpan.org/authors/id/P/PE/PEVANS/Scalar-List-Utils-1.68.tar.gz"
  end
  let(:non_cpan_package_url) do
    "https://github.com/example/package/archive/v1.0.0.tar.gz"
  end

  describe CPAN::Package do
    let(:package_from_cpan_url) { described_class.new("Scalar::Util", cpan_package_url) }
    let(:package_from_non_cpan_url) { described_class.new("SomePackage", non_cpan_package_url) }

    describe "initialize" do
      it "initializes resource name" do
        expect(package_from_cpan_url.name).to eq "Scalar::Util"
      end

      it "extracts package name from CPAN url" do
        expect(package_from_cpan_url.package_name).to eq "Scalar-List-Utils"
      end

      it "extracts version from CPAN url" do
        expect(package_from_cpan_url.current_version).to eq "1.68"
      end
    end

    describe ".valid_cpan_package?" do
      it "is true for CPAN URLs" do
        expect(package_from_cpan_url.valid_cpan_package?).to be true
      end

      it "is false for non-CPAN URLs" do
        expect(package_from_non_cpan_url.valid_cpan_package?).to be false
      end
    end

    describe ".to_s" do
      it "returns resource name" do
        expect(package_from_cpan_url.to_s).to eq "Scalar::Util"
      end
    end
  end
end
