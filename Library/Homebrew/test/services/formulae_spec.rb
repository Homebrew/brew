# frozen_string_literal: true

require "services/formulae"

RSpec.describe Homebrew::Services::Formulae do
  describe "#services_list" do
    it "empty list without available formulae" do
      allow(described_class).to receive(:available_services).and_return({})
      expect(described_class.services_list).to eq([])
    end

    it "list with available formulae" do
      formula = instance_double(Homebrew::Services::FormulaWrapper)
      expected = [
        {
          file:   Pathname.new("/Library/LaunchDaemons/file.plist"),
          name:   "formula",
          status: :known,
          user:   "root",
        },
      ]

      expect(formula).to receive(:to_hash).and_return(expected[0])
      allow(described_class).to receive(:available_services).and_return([formula])
      expect(described_class.services_list).to eq(expected)
    end
  end
end
