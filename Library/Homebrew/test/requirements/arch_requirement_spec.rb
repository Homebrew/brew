# typed: false
# frozen_string_literal: true

require "requirements/arch_requirement"

describe ArchRequirement do
  subject(:requirement) {
    described_class.new(arch)
  }

  describe "#satisfied?" do
    context "when given current architecture" do
      let(:arch) { [Hardware::CPU.type] }

      it "satisfies requirement" do
        expect(requirement).to be_satisfied
      end
    end

    context "when given all architectures" do
      let(:arch) { [:x86_64, :arm64, :arm, :intel, :ppc] }

      it "satisfies requirement" do
        expect(requirement).to be_satisfied
      end
    end

    context "when given empty array" do
      let(:arch) { [] }

      it "satisfies requirement" do
        expect(requirement).to be_satisfied
      end
    end
  end
end
