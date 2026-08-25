# typed: true
# frozen_string_literal: true

require "bottle_specification"

RSpec.describe BottleSpecification do
  subject(:bottle_spec) { described_class.new }

  describe "#sha256" do
    it "works without cellar" do
      checksums = {
        arm64_tahoe: "deadbeef" * 8,
        tahoe:       "faceb00c" * 8,
        sequoia:     "baadf00d" * 8,
        sonoma:      "8badf00d" * 8,
      }

      checksums.each_pair do |cat, digest|
        bottle_spec.sha256(cat => digest)
        tag_spec = bottle_spec.tag_specification_for(Utils::Bottles::Tag.from_symbol(cat))
        expect(Checksum.new(digest)).to eq(tag_spec.checksum)
      end
    end

    it "works with cellar" do
      checksums = [
        { cellar: :any_skip_relocation, tag: :arm64_tahoe, digest: "deadbeef" * 8 },
        { cellar: :any, tag: :tahoe, digest: "faceb00c" * 8 },
        { cellar: "/usr/local/Cellar", tag: :sequoia, digest: "baadf00d" * 8 },
        { cellar: Homebrew::DEFAULT_CELLAR, tag: :sonoma, digest: "8badf00d" * 8 },
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

    it "accepts a longer bottle cellar when build prefix relocation is enabled" do
      ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"] = "1"
      bottle_spec.sha256(cellar: "#{HOMEBREW_CELLAR}-longer", Utils::Bottles.tag.to_sym => "deadbeef" * 8)

      expect(bottle_spec.compatible_locations?).to be true
    end
  end

  describe "#tag_to_cellar" do
    it "returns the cellar for a tag" do
      expect(bottle_spec.tag_to_cellar).to eq Utils::Bottles.tag.default_cellar
    end
  end

  describe "#skip_relocation?" do
    let(:tag) { Utils::Bottles.tag.to_sym }
    let(:digest) { "deadbeef" * 8 }

    it "returns false when there is no matching spec" do
      expect(bottle_spec.skip_relocation?).to be false
    end

    context "when running on Linux", :needs_linux do
      context "with bottle built on Homebrew 5.1.15" do
        let(:tab) { Tab.new(homebrew_version: "5.1.15") }

        it "returns true for `:any_skip_relocation` cellar" do
          bottle_spec.sha256(cellar: :any_skip_relocation, tag => digest)
          expect(bottle_spec.skip_relocation?(tab:)).to be true
        end

        it "returns false for `:any` cellar" do
          bottle_spec.sha256(cellar: :any, tag => digest)
          expect(bottle_spec.skip_relocation?(tab:)).to be false
        end
      end

      context "with bottle built on Homebrew 5.1.14" do
        let(:tab) { Tab.new(homebrew_version: "5.1.14") }

        it "returns false for `:any_skip_relocation` cellar" do
          bottle_spec.sha256(cellar: :any_skip_relocation, tag => digest)
          expect(bottle_spec.skip_relocation?(tab:)).to be false
        end

        it "returns false for `:any` cellar" do
          bottle_spec.sha256(cellar: :any, tag => digest)
          expect(bottle_spec.skip_relocation?(tab:)).to be false
        end
      end

      context "without tab" do
        it "returns false for `:any_skip_relocation` cellar" do
          bottle_spec.sha256(cellar: :any_skip_relocation, tag => digest)
          expect(bottle_spec.skip_relocation?).to be false
        end

        it "returns false for `:any` cellar" do
          bottle_spec.sha256(cellar: :any, tag => digest)
          expect(bottle_spec.skip_relocation?).to be false
        end
      end
    end

    context "when running on macOS", :needs_macos do
      it "returns true for `:any_skip_relocation` cellar" do
        bottle_spec.sha256(cellar: :any_skip_relocation, tag => digest)
        expect(bottle_spec.skip_relocation?).to be true
      end

      it "returns false for `:any` cellar" do
        bottle_spec.sha256(cellar: :any, tag => digest)
        expect(bottle_spec.skip_relocation?).to be false
      end
    end
  end

  specify "#rebuild" do
    bottle_spec.rebuild(1337)
    expect(bottle_spec.rebuild).to eq(1337)
  end

  specify "#root_url" do
    bottle_spec.root_url("https://example.com")
    expect(bottle_spec.root_url).to eq("https://example.com")
  end
end
