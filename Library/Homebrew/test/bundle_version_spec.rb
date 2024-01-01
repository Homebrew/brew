# frozen_string_literal: true

require "bundle_version"

describe Homebrew::BundleVersion do
  describe "#<=>" do
    it "compares both the `short_version` and `version`" do
      expect(described_class.new("1.2.3", "3000")).to be < described_class.new("1.2.3", "4000")
      expect(described_class.new("1.2.3", "4000")).to be <= described_class.new("1.2.3", "4000")
      expect(described_class.new("1.2.3", "4000")).to be >= described_class.new("1.2.3", "4000")
      expect(described_class.new("1.2.4", "4000")).to be > described_class.new("1.2.3", "4000")
    end

    it "compares `version` first" do
      expect(described_class.new("1.2.4", "3000")).to be < described_class.new("1.2.3", "4000")
    end

    it "does not fail when `short_version` or `version` is missing" do
      expect(described_class.new("1.06", nil)).to be < described_class.new("1.12", "1.12")
      expect(described_class.new("1.06", "471")).to be > described_class.new(nil, "311")
      expect(described_class.new("1.2.3", nil)).to be < described_class.new("1.2.4", nil)
      expect(described_class.new(nil, "1.2.3")).to be < described_class.new(nil, "1.2.4")
      expect(described_class.new("1.2.3", nil)).to be < described_class.new(nil, "1.2.3")
      expect(described_class.new(nil, "1.2.3")).to be > described_class.new("1.2.3", nil)
    end
  end

  describe "#nice_version" do
    expected_mappings = {
      ["1.2", nil]            => "1.2",
      [nil, "1.2.3"]          => "1.2.3",
      ["1.2", "1.2.3"]        => "1.2.3",
      ["1.2.3", "1.2"]        => "1.2.3",
      ["1.2.3", "8312"]       => "1.2.3,8312",
      ["2021", "2006"]        => "2021,2006",
      ["1.0", "1"]            => "1.0",
      ["1.0", "0"]            => "1.0",
      ["1.2.3.4000", "4000"]  => "1.2.3.4000",
      ["5", "5.0.45"]         => "5.0.45",
      ["2.5.2(3329)", "3329"] => "2.5.2,3329",
    }

    expected_mappings.each do |(short_version, version), expected_version|
      it "maps (#{short_version.inspect}, #{version.inspect}) to #{expected_version.inspect}" do
        expect(described_class.new(short_version, version).nice_version)
          .to eq expected_version
      end
    end
  end
end
