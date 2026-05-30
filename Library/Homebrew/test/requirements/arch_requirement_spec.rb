# typed: true
# frozen_string_literal: true

require "requirements/arch_requirement"

RSpec.describe ArchRequirement do
  subject(:requirement) { klass.new([Hardware::CPU.type]) }

  let(:klass) { ArchRequirement }

  describe "#satisfied?" do
    it "supports architecture symbols" do
      expect(requirement).to be_satisfied
    end
  end
end
