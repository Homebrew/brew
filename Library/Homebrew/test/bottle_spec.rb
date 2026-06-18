# typed: strict
# frozen_string_literal: true

require "bottle_specification"
require "test/support/fixtures/testball_bottle"

RSpec.describe Bottle do
  describe "#filename" do
    it "renders the bottle filename" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      tag = Utils::Bottles::Tag.from_symbol :arm64_big_sur
      bottle = described_class.new(TestballBottle.new, bottle_spec, tag)

      expect(bottle.filename.to_s).to eq("testball_bottle--0.1.arm64_big_sur.bottle.tar.gz")
    end
  end

  describe "#downloaded_and_valid?" do
    it "trusts cached immutable GitHub Packages bottle blobs matching the expected checksum" do
      tag = Utils::Bottles::Tag.from_symbol(:arm64_big_sur)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(
        cellar:        :any_skip_relocation,
        arm64_big_sur: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      )
      bottle = described_class.new(nil, bottle_spec, tag,
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))

      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("cached")

      expect(bottle.resource).not_to receive(:verify_download_integrity)

      expect(bottle.downloaded_and_valid?).to be true
    end
  end
end
