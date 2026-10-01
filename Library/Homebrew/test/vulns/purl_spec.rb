# typed: strict
# frozen_string_literal: true

require "vulns/purl"

RSpec.describe Homebrew::Vulns::Purl do
  describe "#initialize" do
    it "raises when type is empty" do
      expect { described_class.new(type: "", name: "rails") }.to raise_error(ArgumentError, /type/)
    end

    it "raises when name is empty" do
      expect { described_class.new(type: "gem", name: "") }.to raise_error(ArgumentError, /name/)
    end

    it "lowercases the type and treats empty namespace/version as absent" do
      purl = described_class.new(type: "PyPI", name: "requests", namespace: "", version: "")
      expect(purl.type).to eq "pypi"
      expect(purl.namespace).to be_nil
      expect(purl.version).to be_nil
    end

    it "freezes the stored components" do
      purl = described_class.new(type: "npm", namespace: (+"@babel"), name: (+"core"), version: (+"7.0.0"))
      expect([purl.type, purl.namespace, purl.name, purl.version]).to all be_frozen
    end
  end

  describe "per-type normalisation" do
    it "lowercases a PyPI name and replaces underscores with hyphens" do
      purl = described_class.new(type: "pypi", name: "Types_Setuptools")
      expect(purl.name).to eq "types-setuptools"
    end

    it "leaves PyPI dots and existing hyphens intact" do
      purl = described_class.new(type: "pypi", name: "backports.zoneinfo")
      expect(purl.name).to eq "backports.zoneinfo"
    end

    it "lowercases a Hex name and namespace" do
      purl = described_class.new(type: "hex", namespace: "Acme", name: "Phoenix")
      expect(purl.namespace).to eq "acme"
      expect(purl.name).to eq "phoenix"
    end

    it "uppercases a CPAN namespace and preserves the distribution name" do
      purl = described_class.new(type: "cpan", namespace: "abigail", name: "Regexp-Common")
      expect(purl.namespace).to eq "ABIGAIL"
      expect(purl.name).to eq "Regexp-Common"
    end

    it "does not alter case for cargo, gem, hackage, cran or npm" do
      %w[cargo gem hackage cran npm].each do |type|
        expect(described_class.new(type:, name: "MixedCase").name).to eq "MixedCase"
      end
    end
  end

  describe ".encode" do
    it "leaves the RFC 3986 unreserved set and : untouched" do
      expect(described_class.encode("Az09-._~:")).to eq "Az09-._~:"
    end

    it "percent-encodes @, /, + and space per the purl spec" do
      expect(described_class.encode("@a/b+c d")).to eq "%40a%2Fb%2Bc%20d"
    end

    it "percent-encodes each byte of a multibyte UTF-8 character" do
      expect(described_class.encode("café")).to eq "caf%C3%A9"
    end
  end

  describe "#to_s" do
    it "builds pkg:gem with and without a version, returning a frozen string" do
      bare = described_class.new(type: "gem", name: "rails").to_s
      expect(bare).to eq "pkg:gem/rails"
      expect(bare).to be_frozen
      expect(described_class.new(type: "gem", name: "rails", version: "7.0.0").to_s)
        .to eq "pkg:gem/rails@7.0.0"
    end

    it "builds pkg:npm with an encoded scope namespace" do
      purl = described_class.new(type: "npm", namespace: "@angular", name: "cli", version: "22.0.3")
      expect(purl.to_s).to eq "pkg:npm/%40angular/cli@22.0.3"
    end

    it "builds pkg:pypi with the normalised name" do
      purl = described_class.new(type: "pypi", name: "types_setuptools", version: "80.9.0.20251223")
      expect(purl.to_s).to eq "pkg:pypi/types-setuptools@80.9.0.20251223"
    end

    it "builds pkg:cargo" do
      purl = described_class.new(type: "cargo", name: "cargo-llvm-cov", version: "0.8.7")
      expect(purl.to_s).to eq "pkg:cargo/cargo-llvm-cov@0.8.7"
    end

    it "builds pkg:hackage preserving case" do
      purl = described_class.new(type: "hackage", name: "Allure", version: "0.11.0.0")
      expect(purl.to_s).to eq "pkg:hackage/Allure@0.11.0.0"
    end

    it "builds pkg:hex with a lowercased name" do
      purl = described_class.new(type: "hex", name: "Phoenix", version: "1.7.0-rc.0")
      expect(purl.to_s).to eq "pkg:hex/phoenix@1.7.0-rc.0"
    end

    it "builds pkg:cpan with an uppercased author namespace" do
      purl = described_class.new(type: "cpan", namespace: "ABIGAIL", name: "Regexp-Common",
                                 version: "2024080801")
      expect(purl.to_s).to eq "pkg:cpan/ABIGAIL/Regexp-Common@2024080801"
    end

    it "builds pkg:maven with a groupId namespace" do
      purl = described_class.new(type: "maven", namespace: "com.github.spotbugs", name: "spotbugs",
                                 version: "4.10.2")
      expect(purl.to_s).to eq "pkg:maven/com.github.spotbugs/spotbugs@4.10.2"
    end

    it "builds pkg:cran" do
      purl = described_class.new(type: "cran", name: "data.table", version: "1.15.4")
      expect(purl.to_s).to eq "pkg:cran/data.table@1.15.4"
    end

    it "builds pkg:nuget" do
      purl = described_class.new(type: "nuget", name: "Newtonsoft.Json", version: "13.0.3")
      expect(purl.to_s).to eq "pkg:nuget/Newtonsoft.Json@13.0.3"
    end

    it "encodes semver build metadata + in the version" do
      purl = described_class.new(type: "cargo", name: "foo", version: "1.0.0+build.1")
      expect(purl.to_s).to eq "pkg:cargo/foo@1.0.0%2Bbuild.1"
    end

    it "encodes each namespace segment separately, preserving the / separator" do
      purl = described_class.new(type: "golang", namespace: "github.com/gorilla", name: "mux",
                                 version: "v1.8.1")
      expect(purl.to_s).to eq "pkg:golang/github.com/gorilla/mux@v1.8.1"
    end
  end

  describe "#== and #hash" do
    it "considers two purls equal when their canonical strings match" do
      a = described_class.new(type: "PyPI", name: "Foo_Bar", version: "1.0")
      b = described_class.new(type: "pypi", name: "foo-bar", version: "1.0")
      expect(a).to eq b
      expect(a.hash).to eq b.hash
    end

    it "is not equal to a purl with a different version" do
      a = described_class.new(type: "gem", name: "rails", version: "7.0.0")
      b = described_class.new(type: "gem", name: "rails", version: "7.0.1")
      expect(a).not_to eq b
    end

    it "is not equal to a plain string" do
      purl = described_class.new(type: "gem", name: "rails")
      expect(purl == "pkg:gem/rails").to be false
    end
  end
end
