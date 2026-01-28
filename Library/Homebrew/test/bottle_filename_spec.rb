# frozen_string_literal: true

require "formula"
require "software_spec"

RSpec.describe Bottle::Filename do
  subject(:filename) { described_class.new(name, version, tag, rebuild) }

  let(:name) { "user/repo/foo" }
  let(:version) { PkgVersion.new(Version.new("1.0"), 0) }
  let(:tag) { Utils::Bottles::Tag.from_symbol(:x86_64_linux) }
  let(:rebuild) { 0 }

  describe "#extname" do
    it(:extname) { expect(filename.extname).to eq ".x86_64_linux.bottle.tar.gz" }

    context "when rebuild is 0" do
      it(:extname) { expect(filename.extname).to eq ".x86_64_linux.bottle.tar.gz" }
    end

    context "when rebuild is 1" do
      let(:rebuild) { 1 }

      it(:extname) { expect(filename.extname).to eq ".x86_64_linux.bottle.1.tar.gz" }
    end
  end

  describe "#to_s and #to_str" do
    it(:to_s) { expect(filename.to_s).to eq "foo--1.0.x86_64_linux.bottle.tar.gz" }
    it(:to_str) { expect(filename.to_str).to eq "foo--1.0.x86_64_linux.bottle.tar.gz" }
  end

  describe "#url_encode" do
    it(:url_encode) { expect(filename.url_encode).to eq "foo-1.0.x86_64_linux.bottle.tar.gz" }
  end

  describe "#github_packages" do
    it(:github_packages) { expect(filename.github_packages).to eq "foo--1.0.x86_64_linux.bottle.tar.gz" }
  end

  describe "#json" do
    it(:json) { expect(filename.json).to eq "foo--1.0.x86_64_linux.bottle.json" }

    context "when rebuild is 1" do
      it(:json) { expect(filename.json).to eq "foo--1.0.x86_64_linux.bottle.json" }
    end
  end

  describe "::create" do
    subject(:filename) { described_class.create(f, tag, rebuild) }

    let(:f) do
      formula do
        url "https://brew.sh/foo.tar.gz"
        version "1.0"
      end
    end

    it(:to_s) { expect(filename.to_s).to eq "formula_name--1.0.x86_64_linux.bottle.tar.gz" }
  end
end
