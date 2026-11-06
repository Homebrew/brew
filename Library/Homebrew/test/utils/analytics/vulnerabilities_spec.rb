# typed: strict
# frozen_string_literal: true

require "utils/analytics/vulnerabilities"

RSpec.describe Utils::Analytics::Vulnerabilities do
  it "separates withdrawn and uncomparable records without counting upstream identifiers as unique vulnerabilities" do
    mktmpdir do |repository|
      (repository/"advisories").mkpath
      [
        ["foo", "CVE-1", "patch", nil, nil],
        ["bar", "CVE-1", nil, "affected", nil],
        ["foo", "CVE-2", nil, nil, nil],
        %w[foo CVE-3 bump fixed 2025-01-01],
      ].each_with_index do |(name, upstream, fix, state, withdrawn), index|
        (repository/"advisories/#{index}.json").write(JSON.generate({
          id: "BREW-#{name}-#{upstream}", upstream: [upstream], withdrawn:,
          database_specific: { source: (fix == "patch") ? "generated" : "matched" },
          affected: [{ package: { name: }, ecosystem_specific: { fix:, range_state: state } }]
        }))
      end

      expect(described_class.corpus(repository).fetch("counts")).to include(
        "records" => 4, "withdrawn" => 1, "formulae" => 2, "upstream_identifiers" => 2,
        "patch" => 1, "unresolved" => 1, "uncomparable" => 1
      )
    end
  end

  it "counts current formula findings and distinguishes uncovered formulae from covered formulae without findings" do
    data = described_class.catalogue({
      "foo" => { "vulnerabilities" => { "open" => [{ "severity" => "critical", "upstream" => ["CVE-1"] }],
                                        "patched" => [{ "id" => "BREW-foo-CVE-2" }], "fixed_count" => 2 } },
      "bar" => { "vulnerabilities" => { "open" => [], "patched" => [], "fixed_count" => 1 } },
      "baz" => {},
    }, available: true, revision: "abc123")

    expect(data).to include("counts"   => include("catalogue_formulae" => 3, "covered_formulae" => 2,
                                                  "uncovered_formulae" => 1, "open" => 1, "patched" => 1,
                                                  "fixed" => 3, "open_upstream_identifiers" => 1),
                            "severity" => { "critical" => 1 })
  end
end
