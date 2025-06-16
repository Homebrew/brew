# frozen_string_literal: true

require "requirements/arch_requirement"

RSpec.describe ArchRequirement do
  subject(:requirement) { described_class.new([Hardware::CPU.type]) }

  describe "#satisfied?" do
    it "supports architecture symbols" do
      expect(requirement).to be_satisfied
    end
  end
end
