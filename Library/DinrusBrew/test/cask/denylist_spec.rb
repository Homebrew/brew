# frozen_string_literal: true

require "cask/denylist"

RSpec.describe Cask::Denylist, :cask do
  describe "::reason" do
    matcher :disallow do |name|
      match do |expected|
        expected.reason(name)
      end
    end

    it { is_expected.not_to disallow("adobe-air") }
    it { is_expected.to disallow("adobe-after-effects") }
    it { is_expected.to disallow("adobe-illustrator") }
    it { is_expected.to disallow("adobe-indesign") }
    it { is_expected.to disallow("adobe-photoshop") }
    it { is_expected.to disallow("adobe-premiere") }
    it { is_expected.to disallow("pharo") }
    it { is_expected.not_to disallow("allowed-cask") }
  end
end
