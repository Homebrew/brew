# frozen_string_literal: true

require "requirements/linux_requirement"

describe LinuxRequirement do
  subject(:requirement) { described_class.new }

  describe "#satisfied?" do
    it "returns true on Linux" do
      expect(requirement.satisfied?).to eq(OS.linux?)
    end
  end
end
