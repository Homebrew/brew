# frozen_string_literal: true

require "cask/denylist"

RSpec.describe Cask::Denylist, :cask do
  describe "::reason" do
    matcher :disallow do |name|
      match do |expected|
        expected.reason(name)
      end
    end

    specify(:aggregate_failures) do
      expect(subject).not_to disallow("adobe-air") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("adobe-after-effects") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("adobe-illustrator") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("adobe-indesign") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("adobe-photoshop") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("adobe-premiere") # rubocop:todo RSpec/NamedSubject
      expect(subject).to disallow("pharo") # rubocop:todo RSpec/NamedSubject
      expect(subject).not_to disallow("allowed-cask") # rubocop:todo RSpec/NamedSubject
    end
  end
end
