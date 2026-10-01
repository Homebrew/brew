# typed: strict
# frozen_string_literal: true

require "cask/denylist"

RSpec.describe Cask::Denylist, :cask do
  describe "::reason" do
    matcher :disallow do |name|
      T.bind(self, T.class_of(RSpec::Matchers::DSL::Matcher))
      match do |expected|
        expected.reason(name)
      end
    end

    specify(:aggregate_failures) do
      expect(described_class).not_to disallow("adobe-air")
      expect(described_class).to disallow("adobe-after-effects")
      expect(described_class).to disallow("adobe-illustrator")
      expect(described_class).to disallow("adobe-indesign")
      expect(described_class).to disallow("adobe-photoshop")
      expect(described_class).to disallow("adobe-premiere")
      expect(described_class).to disallow("pharo")
      expect(described_class).not_to disallow("allowed-cask")
    end
  end
end
