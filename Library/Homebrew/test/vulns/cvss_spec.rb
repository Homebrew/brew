# typed: false
# frozen_string_literal: true

require "vulns/cvss"

RSpec.describe Homebrew::Vulns::CVSS do
  describe ".base_score" do
    # Vectors and expected scores from FIRST CVSS v3.1 examples and NVD entries
    # used in the brew-vulns gem's test suite.
    {
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" => 9.8,
      "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" => 9.8,
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:H" => 9.6,
      "CVSS:3.0/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:H" => 9.6,
      "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H" => 8.8,
      "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H" => 8.8,
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H" => 8.8,
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N" => 7.5,
      "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:L/I:L/A:N" => 6.4,
      "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N" => 5.5,
      "CVSS:3.1/AV:N/AC:H/PR:N/UI:R/S:C/C:L/I:L/A:N" => 4.7,
      "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:N" => 3.8,
      "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N" => 1.8,
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N" => 0.0,
      "CVSS:3.1/AV:P/AC:H/PR:H/UI:R/S:U/C:N/I:N/A:N" => 0.0,
    }.each do |vector, score|
      it "scores #{vector} as #{score}" do
        expect(described_class.base_score(vector)).to eq score
      end
    end

    it "ignores temporal and environmental metrics" do
      vector = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H/E:P/RL:O/RC:C"
      expect(described_class.base_score(vector)).to eq 9.8
    end

    it "returns nil for CVSS v4.0 vectors" do
      expect(described_class.base_score(
               "CVSS:4.0/AV:N/AC:L/AT:N/PR:H/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N",
             )).to be_nil
    end

    it "returns nil for CVSS v2 vectors" do
      expect(described_class.base_score("AV:N/AC:L/Au:N/C:C/I:C/A:C")).to be_nil
    end

    it "returns nil for a vector missing required base metrics" do
      expect(described_class.base_score("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H")).to be_nil
    end

    it "returns nil for a vector with an unknown metric value" do
      expect(described_class.base_score("CVSS:3.1/AV:X/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H")).to be_nil
    end

    it "returns nil for garbage input" do
      expect(described_class.base_score("")).to be_nil
      expect(described_class.base_score("INVALID-CVSS")).to be_nil
      expect(described_class.base_score("CVSS:3.1/")).to be_nil
    end
  end

  describe ".severity" do
    # Vectors from brew-vulns test/brew/test_vulnerability.rb
    it "buckets a 9.8 vector as critical" do
      expect(described_class.severity("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H")).to eq :critical
    end

    it "buckets an 8.8 vector as high" do
      expect(described_class.severity("CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H")).to eq :high
    end

    it "buckets a 5.5 vector as medium" do
      expect(described_class.severity("CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N")).to eq :medium
    end

    it "buckets a 1.8 vector as low" do
      expect(described_class.severity("CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N")).to eq :low
    end

    it "returns nil for a zero-impact vector" do
      expect(described_class.severity("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N")).to be_nil
    end

    it "returns nil for an unsupported version" do
      expect(described_class.severity(
               "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
             )).to be_nil
    end

    it "returns nil for an unparseable vector" do
      expect(described_class.severity("INVALID-CVSS")).to be_nil
    end
  end
end
