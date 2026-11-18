# typed: true
# frozen_string_literal: true

require "requirements/linux_requirement"

RSpec.describe LinuxRequirement do
  subject(:requirement) { described_class.new }

  describe "#satisfied?" do
    it "returns true on Linux" do
      expect(requirement.satisfied?).to eq(OS.linux?)
    end
  end

  describe "#platform_supported?" do
    test_each([[:x86_64_linux, true], [:sonoma, false]]) do |(tag, supported)|
      it "is #{supported} on #{tag}" do
        expect(requirement.platform_supported?(Utils::Bottles::Tag.from_symbol(tag))).to be(supported)
      end
    end
  end
end
