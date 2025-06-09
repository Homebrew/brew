# frozen_string_literal: true

require "requirements/macos_requirement"

RSpec.describe MacOSRequirement do
  subject(:requirement) { described_class.new }

  let(:macos_oldest_allowed) { MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED) }
  let(:macos_newest_allowed) { MacOSVersion.new(HOMEBREW_MACOS_NEWEST_UNSUPPORTED) }
  let(:macos_newest_supported) { MacOSVersion.new(MacOSVersion::SYMBOLS.values.first) }
  let(:big_sur_major) { MacOSVersion.new("11.0") }

  describe "#satisfied?" do
    it "returns true on macOS" do
      expect(requirement.satisfied?).to eq OS.mac?
    end

    it "supports version symbols", :needs_macos do
      requirement = described_class.new([MacOS.version.to_sym])
      expect(requirement).to be_satisfied
    end

    it "supports maximum versions", :needs_macos do
      requirement = described_class.new([:catalina], comparator: "<=")
      expect(requirement.satisfied?).to eq MacOS.version <= :catalina
    end
  end

  specify "#minimum_version" do
    no_requirement = described_class.new
    max_requirement = described_class.new([:big_sur], comparator: "<=")
    min_requirement = described_class.new([:big_sur], comparator: ">=")
    exact_requirement = described_class.new([:big_sur], comparator: "==")
    range_requirement = described_class.new([[:monterey, :big_sur]], comparator: "==")
    expect(no_requirement.minimum_version).to eq macos_oldest_allowed
    expect(max_requirement.minimum_version).to eq macos_oldest_allowed
    expect(min_requirement.minimum_version).to eq big_sur_major
    expect(exact_requirement.minimum_version).to eq big_sur_major
    expect(range_requirement.minimum_version).to eq big_sur_major
  end

  specify "#maximum_version" do
    no_requirement = described_class.new
    max_requirement = described_class.new([:big_sur], comparator: "<=")
    min_requirement = described_class.new([:big_sur], comparator: ">=")
    exact_requirement = described_class.new([:big_sur], comparator: "==")
    range_requirement = described_class.new([[:catalina, :big_sur]], comparator: "==")
    expect(no_requirement.maximum_version).to eq macos_newest_allowed
    expect(max_requirement.maximum_version).to eq big_sur_major
    expect(min_requirement.maximum_version).to eq macos_newest_allowed
    expect(exact_requirement.maximum_version).to eq big_sur_major
    expect(range_requirement.maximum_version).to eq big_sur_major
  end

  specify "#allows?" do
    no_requirement = described_class.new
    max_requirement = described_class.new([:mojave], comparator: "<=")
    min_requirement = described_class.new([:catalina], comparator: ">=")
    exact_requirement = described_class.new([:big_sur], comparator: "==")
    range_requirement = described_class.new([[:monterey, :big_sur]], comparator: "==")
    expect(no_requirement.allows?(big_sur_major)).to be true
    expect(max_requirement.allows?(big_sur_major)).to be false
    expect(min_requirement.allows?(big_sur_major)).to be true
    expect(exact_requirement.allows?(big_sur_major)).to be true
    expect(range_requirement.allows?(big_sur_major)).to be true
  end

  specify "#highest_allowed" do
    macos_version_sonoma = MacOSVersion.new("14")

    no_requirement = described_class.new
    max_requirement = described_class.new([:sonoma], comparator: "<=")
    min_requirement = described_class.new([:sonoma], comparator: ">=")
    exact_requirement = described_class.new([:sonoma], comparator: "==")
    range_requirement = described_class.new([[:sonoma, :monterey]], comparator: "==")
    expect(no_requirement.highest_allowed).to eq macos_newest_supported
    expect(max_requirement.highest_allowed).to eq macos_version_sonoma
    expect(min_requirement.highest_allowed).to eq macos_newest_supported
    expect(exact_requirement.highest_allowed).to eq macos_version_sonoma
    expect(range_requirement.highest_allowed).to eq macos_version_sonoma
  end
end
