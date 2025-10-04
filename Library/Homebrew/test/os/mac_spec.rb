# frozen_string_literal: true

require "locale"
require "os/mac"

RSpec.describe OS::Mac do
  describe "::languages" do
    it "returns a list of all languages" do
      expect(described_class.languages).not_to be_empty
    end
  end

  describe "::language" do
    it "returns the first item from #languages" do
      expect(described_class.language).to eq(described_class.languages.first)
    end
  end
end
