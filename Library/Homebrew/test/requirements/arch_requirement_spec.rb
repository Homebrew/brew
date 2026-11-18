# typed: true
# frozen_string_literal: true

require "requirements/arch_requirement"

RSpec.describe ArchRequirement do
  subject(:requirement) { described_class.new([Hardware::CPU.type]) }

  describe "#satisfied?" do
    it "supports architecture symbols" do
      expect(requirement).to be_satisfied
    end
  end

  describe "#platform_supported?" do
    subject(:requirement) { described_class.new([:arm64]) }

    test_each([[:arm64_sonoma, true], [:arm64_linux, true], [:sonoma, false]]) do |(tag, supported)|
      it "is #{supported} on #{tag}" do
        expect(requirement.platform_supported?(Utils::Bottles::Tag.from_symbol(tag))).to be(supported)
      end
    end
  end
end
