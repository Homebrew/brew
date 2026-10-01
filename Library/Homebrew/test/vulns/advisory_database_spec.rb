# typed: true
# frozen_string_literal: true

require "vulns/advisory_database"

RSpec.describe Homebrew::Vulns::AdvisoryDatabase do
  def record(id, formula, events:, fix: nil, upstream: nil, summary: nil, severity: nil)
    {
      "id"       => id,
      "upstream" => upstream,
      "summary"  => summary,
      "severity" => severity,
      "affected" => [{
        "package"            => { "ecosystem" => "Homebrew", "name" => formula },
        "ranges"             => [{ "type" => "ECOSYSTEM", "events" => events }],
        "ecosystem_specific" => { "fix" => fix },
      }],
    }.compact
  end

  def db(by_formula)
    described_class.new({ "meta"       => { "count" => by_formula.each_value.sum(&:size) },
                          "advisories" => by_formula })
  end

  describe "#initialize" do
    it "raises Error when the top-level value is not a JSON object" do
      expect { described_class.new([]) }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /not a JSON object/)
    end

    it "raises Error when the advisories key is missing" do
      expect { described_class.new({ "meta" => {} }) }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /no 'advisories' key/)
    end

    it "distinguishes a wrong-type advisories value from a missing key" do
      expect { described_class.new({ "advisories" => [] }) }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /'advisories' is not a JSON object/)
    end
  end

  describe "#records_for" do
    it "wraps each record for the formula in a Vulnerability" do
      d = db({ "unzip" => [record("BREW-unzip-CVE-1", "unzip",
                                  events: [{ "introduced" => "0" }, { "fixed" => "6.0_29" }])] })
      expect(d.records_for("unzip").map(&:id)).to eq ["BREW-unzip-CVE-1"]
      expect(d.records_for("unzip").first).to be_a Homebrew::Vulns::Vulnerability
    end

    it "returns [] for a formula with no records" do
      expect(db({}).records_for("nope")).to eq []
    end
  end

  describe "#status_for" do
    let(:corpus) do
      db({
        "unzip" => [
          record("BREW-unzip-CVE-2014-8139", "unzip",
                 events: [{ "introduced" => "0" }, { "fixed" => "6.0_29" }],
                 fix: "patch", upstream: ["CVE-2014-8139"], summary: "s",
                 severity: [{ "type"  => "CVSS_V3",
                              "score" => "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" }]),
          record("BREW-unzip-CVE-2021-4217", "unzip",
                 events:   [{ "introduced" => "0" }],
                 upstream: ["CVE-2021-4217"]),
          record("BREW-unzip-CVE-2016-0001", "unzip",
                 events: [{ "introduced" => "0" }, { "fixed" => "6.0_10" }],
                 fix: "bump", upstream: ["CVE-2016-0001"]),
        ],
      })
    end

    it "partitions into open (still in range), patched (fix: patch, past range), and fixed_count" do
      status = corpus.status_for("unzip", "6.0_29")

      expect(status["open"].map { |e| e["id"] }).to eq ["BREW-unzip-CVE-2021-4217"]
      expect(status["open"].first["upstream"]).to eq ["CVE-2021-4217"]
      expect(status["patched"].map { |e| e["id"] }).to eq ["BREW-unzip-CVE-2014-8139"]
      expect(status["patched"].first["severity"]).to eq "critical"
      expect(status["patched"].first["fixed_in"]).to eq "6.0_29"
      expect(status["fixed_count"]).to eq 1
    end

    it "counts a patch record whose fixed boundary is above pkg_version as open" do
      status = corpus.status_for("unzip", "6.0_28")
      expect(status["open"].map { |e| e["id"] })
        .to contain_exactly("BREW-unzip-CVE-2014-8139", "BREW-unzip-CVE-2021-4217")
      expect(status["patched"]).to eq []
    end

    it "returns nil when the corpus has no records for the formula" do
      expect(corpus.status_for("nope", "1.0")).to be_nil
    end

    it "ignores :not_applicable records rather than counting them as fixed or patched" do
      d = db({ "foo" => [
        record("BREW-foo-CVE-1", "foo",
               events: [{ "introduced" => "2.0" }, { "fixed" => "3.0" }], fix: "bump"),
        record("BREW-foo-CVE-2", "foo",
               events: [{ "introduced" => "2.0" }, { "fixed" => "3.0" }], fix: "patch"),
      ] })
      status = d.status_for("foo", "1.0")
      expect(status["open"]).to eq []
      expect(status["patched"]).to eq []
      expect(status["fixed_count"]).to eq 0
    end

    it "compacts nil fields out of each entry hash" do
      status = corpus.status_for("unzip", "6.0_29")
      expect(status["open"].first.keys).to eq %w[id upstream]
    end

    it "accepts a PkgVersion" do
      require "pkg_version"
      expect(corpus.status_for("unzip", PkgVersion.parse("6.0_29"))["fixed_count"]).to eq 1
    end
  end

  describe "#formulae and #meta" do
    it "exposes the index keys and meta block" do
      d = db({ "a" => [], "b" => [] })
      expect(d.formulae).to contain_exactly("a", "b")
      expect(d.meta["count"]).to eq 0
    end
  end
end
