# frozen_string_literal: true

require "software_spec"
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
end
