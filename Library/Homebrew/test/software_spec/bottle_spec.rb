# frozen_string_literal: true

require "software_spec"

describe BottleSpecification do
  subject(:bottle_spec) { described_class.new }

  describe "#sha256" do
    it "works without cellar" do
      checksums = {
        arm64_big_sur: "deadbeef" * 8,
        big_sur:       "faceb00c" * 8,
        catalina:      "baadf00d" * 8,
        mojave:        "8badf00d" * 8,
      }

      checksums.each_pair do |cat, digest|
        bottle_spec.sha256(cat => digest)
        tag_spec = bottle_spec.tag_specification_for(Utils::Bottles::Tag.from_symbol(cat))
        expect(Checksum.new(digest)).to eq(tag_spec.checksum)
      end
    end

    it "works with cellar" do
      checksums = [
        { cellar: :any_skip_relocation, tag: :arm64_big_sur,  digest: "deadbeef" * 8 },
        { cellar: :any, tag: :big_sur, digest: "faceb00c" * 8 },
        { cellar: "/usr/local/Cellar", tag: :catalina, digest: "baadf00d" * 8 },
        { cellar: Homebrew::DEFAULT_CELLAR, tag: :mojave, digest: "8badf00d" * 8 },
      ]

      checksums.each do |checksum|
        bottle_spec.sha256(cellar: checksum[:cellar], checksum[:tag] => checksum[:digest])
        tag_spec = bottle_spec.tag_specification_for(Utils::Bottles::Tag.from_symbol(checksum[:tag]))
        expect(Checksum.new(checksum[:digest])).to eq(tag_spec.checksum)
        expect(checksum[:tag]).to eq(tag_spec.tag.to_sym)
        checksum[:cellar] ||= Homebrew::DEFAULT_CELLAR
        expect(checksum[:cellar]).to eq(tag_spec.cellar)
      end
    end
  end

  describe "#compatible_locations?" do
    it "checks if the bottle cellar is relocatable" do
      expect(bottle_spec.compatible_locations?).to be false
    end
  end

  describe "#tag_to_cellar" do
    it "returns the cellar for a tag" do
      expect(bottle_spec.tag_to_cellar).to eq Utils::Bottles.tag.default_cellar
    end
  end

  %w[root_url rebuild].each do |method|
    specify "##{method}" do
      object = Object.new
      bottle_spec.public_send(method, object)
      expect(bottle_spec.public_send(method)).to eq(object)
    end
  end
end
