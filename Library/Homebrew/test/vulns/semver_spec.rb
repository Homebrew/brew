# typed: strict
# frozen_string_literal: true

require "vulns/semver"

RSpec.describe Homebrew::Vulns::Semver do
  describe ".compare" do
    # From vers gem: basic numeric ordering
    it "orders major versions numerically" do
      expect(described_class.compare("1.0.0", "2.0.0")).to eq(-1)
      expect(described_class.compare("2.0.0", "1.9.9")).to eq 1
      expect(described_class.compare("1.0.0", "1.0.0")).to eq 0
    end

    it "orders minor and patch versions numerically" do
      expect(described_class.compare("1.9.0", "1.10.0")).to eq(-1)
      expect(described_class.compare("1.0.9", "1.0.10")).to eq(-1)
    end

    it "treats missing minor/patch as zero" do
      expect(described_class.compare("1", "1.0.0")).to eq 0
      expect(described_class.compare("1.2", "1.2.0")).to eq 0
    end

    it "strips a leading v prefix" do
      expect(described_class.compare("v1.2.3", "1.2.3")).to eq 0
      expect(described_class.compare("V2.0.0", "1.9.9")).to eq 1
    end

    # SemVer 2.0 spec section 11: build metadata is ignored for precedence
    it "ignores build metadata" do
      expect(described_class.compare("1.0.0+1", "1.0.0+2")).to eq 0
      expect(described_class.compare("1.0.0+20130313144700", "1.0.0")).to eq 0
      expect(described_class.compare("1.0.0-beta+exp.sha.5114f85", "1.0.0-beta")).to eq 0
    end

    # SemVer 2.0 spec section 11: a version with a prerelease has lower
    # precedence than the same version without one
    it "orders prerelease below the associated release" do
      expect(described_class.compare("1.0.0-alpha", "1.0.0")).to eq(-1)
      expect(described_class.compare("1.0.0", "1.0.0-rc.1")).to eq 1
    end

    # SemVer 2.0 spec section 11: prerelease identifiers compared field by field
    it "compares numeric prerelease identifiers numerically" do
      expect(described_class.compare("1.0.0-alpha.9", "1.0.0-alpha.10")).to eq(-1)
      expect(described_class.compare("1.0.0-1", "1.0.0-2")).to eq(-1)
    end

    it "compares alphanumeric prerelease identifiers lexically" do
      expect(described_class.compare("1.0.0-alpha", "1.0.0-beta")).to eq(-1)
      expect(described_class.compare("1.0.0-rc", "1.0.0-beta")).to eq 1
    end

    # SemVer 2.0 spec section 11 rule 3: numeric identifiers always have lower
    # precedence than alphanumeric identifiers
    it "orders numeric prerelease identifiers below alphanumeric ones" do
      expect(described_class.compare("1.0.0-alpha.1", "1.0.0-alpha.beta")).to eq(-1)
      expect(described_class.compare("1.0.0-2", "1.0.0-1a")).to eq(-1)
    end

    # SemVer 2.0 spec section 11 rule 4: a larger set of prerelease fields has
    # higher precedence than a smaller set, if all preceding identifiers match
    it "orders shorter prerelease field lists below longer ones" do
      expect(described_class.compare("1.0.0-alpha", "1.0.0-alpha.1")).to eq(-1)
    end

    # SemVer 2.0 spec section 11: full precedence chain example
    it "matches the spec's precedence example chain" do
      chain = %w[
        1.0.0-alpha
        1.0.0-alpha.1
        1.0.0-alpha.beta
        1.0.0-beta
        1.0.0-beta.2
        1.0.0-beta.11
        1.0.0-rc.1
        1.0.0
      ]
      chain.each_cons(2) do |pair|
        a = pair.fetch(0)
        b = pair.fetch(1)
        expect(described_class.compare(a, b)).to(eq(-1), "expected #{a} < #{b}")
        expect(described_class.compare(b, a)).to(eq(1), "expected #{b} > #{a}")
      end
    end

    # From brew-vulns test_vulnerability.rb: OSV uses "0" as an open lower bound
    it "handles single-segment zero" do
      expect(described_class.compare("0", "0.1.0")).to eq(-1)
      expect(described_class.compare("0", "0.0.0")).to eq 0
    end

    # From brew-vulns test_vulnerability.rb range checks
    it "handles versions used in OSV range fixtures" do
      expect(described_class.compare("1.2.0", "1.5.0")).to eq(-1)
      expect(described_class.compare("1.4.9", "1.5.0")).to eq(-1)
      expect(described_class.compare("1.5.0", "1.5.0")).to eq 0
      expect(described_class.compare("4.17.20", "4.17.21")).to eq(-1)
    end

    it "returns nil when either side is unparseable" do
      expect(described_class.compare("not-a-version", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0", "")).to be_nil
    end

    it "returns nil for leading zeroes in core segments" do
      expect(described_class.compare("01.0.0", "1.0.0")).to be_nil
      expect(described_class.compare("1.02.0", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.00", "1.0.0")).to be_nil
    end

    it "returns nil for leading zeroes in numeric prerelease identifiers" do
      expect(described_class.compare("1.0.0-01", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0-alpha.01", "1.0.0")).to be_nil
    end

    it "accepts leading zeroes in alphanumeric prerelease identifiers" do
      expect(described_class.compare("1.0.0-0a", "1.0.0-0a")).to eq 0
    end

    it "returns nil for empty prerelease or build identifiers" do
      expect(described_class.compare("1.0.0-", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0-alpha..1", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0-alpha.", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0+", "1.0.0")).to be_nil
      expect(described_class.compare("1.0.0+build..1", "1.0.0")).to be_nil
    end
  end
end
