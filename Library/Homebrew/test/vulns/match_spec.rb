# typed: true
# frozen_string_literal: true

require "vulns/match"

RSpec.describe Homebrew::Vulns::Match do
  let(:repology) do
    Homebrew::Vulns::Repology.new({ "meta" => {}, "formulae" => {
      "requests" => { "Debian" => ["requests"], "Alpine" => ["py3-requests"] },
    } })
  end
  let(:cpan_sec) do
    Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {
      "Image-ExifTool" => { "advisories" => [
        { "id" => "CPANSA-Image-ExifTool-2021-22204", "cves" => ["CVE-2021-22204"],
          "affected_versions" => ["<12.24"], "fixed_versions" => [">=12.24"] },
      ] },
    } })
  end
  let(:matcher) { described_class.new(repology:, cpan_sec:) }

  def stub_repology_lookup(result = {})
    allow(Homebrew::Vulns::Repology).to receive(:lookup).and_return(result)
  end

  def vuln(data)
    Homebrew::Vulns::Vulnerability.new(data)
  end

  def ev(strategy, ecosystem: nil, name: nil, subject_version: nil, key: "k", resource: nil, advisory: nil)
    Homebrew::Vulns::Match::Evidence.new(strategy:, ecosystem:, name:, subject_version:, key:,
                                         resource:, advisory:)
  end

  def make_hit(vulnerability, *evidence)
    Homebrew::Vulns::Match::Hit.new(vulnerability:, evidence:)
  end

  def pnpm_overrides
    Homebrew::Vulns::AdvisoryOverrides.new({
      "pnpm" => { "registry_package" => {
        "ecosystem" => "npm",
        "name"      => "pnpm",
      } },
    })
  end

  describe "#identify" do
    it "uses an explicit registry package when the source URL is not a registry archive" do
      overridden = described_class.new(repology:, cpan_sec:, overrides: pnpm_overrides)
      pnpm = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/pnpm/pnpm/archive/refs/tags/v12.3.4.tar.gz"
      end

      expect(overridden.identify(pnpm).primary_package.to_h).to eq(
        ecosystem: "npm",
        name:      "pnpm",
        version:   "12.3.4",
        purl:      "pkg:npm/pnpm@12.3.4",
      )
    end

    it "rejects an explicit registry package that conflicts with the source URL" do
      overridden = described_class.new(repology:, cpan_sec:, overrides: pnpm_overrides)
      pnpm = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/not-pnpm/-/not-pnpm-12.3.4.tgz"
      end

      expect { overridden.identify(pnpm) }
        .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /conflicts with its source URL/)
    end

    it "keeps the source-derived package when the formula has no stable version" do
      overridden = described_class.new(repology:, cpan_sec:, overrides: pnpm_overrides)
      pnpm = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/pnpm/-/pnpm-12.3.4.tgz"
      end
      stable = pnpm.stable
      allow(stable).to receive(:version).and_return(nil)
      allow(pnpm).to receive(:stable).and_return(stable)

      expect(overridden.identify(pnpm).primary_package&.name).to eq "pnpm"
    end

    it "derives git repo/tag, primary registry package, resources and distro packages" do
      f = formula("requests") do
        T.bind(self, T.class_of(Formula))
        homepage "https://requests.readthedocs.io"
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
        head "https://github.com/psf/requests.git"
        resource "certifi" do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-2024.2.2.tar.gz"
        end
        resource "vendored-c" do
          url "https://example.com/blob-1.0.tar.gz"
        end
      end

      identity = matcher.identify(f)

      expect(identity.git_repo).to eq "https://github.com/psf/requests"
      expect(identity.git_tag).to eq "2.31.0"
      expect(identity.primary_package.ecosystem).to eq "PyPI"
      expect(identity.primary_package.name).to eq "requests"
      expect(identity.resource_packages.keys).to eq ["certifi"]
      expect(identity.resource_packages["certifi"].purl).to eq "pkg:pypi/certifi@2024.2.2"
      expect(identity.distro_packages)
        .to eq("Debian" => ["requests"], "Alpine" => ["py3-requests"])
      expect(identity.identifiable?).to be true
    end

    it "falls back to Repology.lookup when the index has no entry (single-formula mode)" do
      f = formula("newthing") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/newthing-1.0.tar.gz"
      end
      stub_repology_lookup({ "Debian" => ["newthing"] })

      expect(matcher.identify(f).distro_packages).to eq("Debian" => ["newthing"])
    end

    it "does not fall back to Repology.lookup in bulk mode" do
      f = formula("newthing") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/newthing-1.0.tar.gz"
      end
      expect(Homebrew::Vulns::Repology).not_to receive(:lookup)

      bulk = described_class.new(repology:, cpan_sec:, bulk: true)
      expect(bulk.identify(f).distro_packages).to eq({})
    end

    it "swallows a Repology lookup error to an empty distro map" do
      f = formula("newthing") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/newthing-1.0.tar.gz"
      end
      allow(Homebrew::Vulns::Repology).to receive(:lookup)
        .and_raise(Homebrew::Vulns::CachedFeed::Error, "boom")

      expect(matcher.identify(f).distro_packages).to eq({})
    end

    it "reports identifiable? false when nothing is derivable" do
      f = formula("mystery") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/mystery-1.0.tar.gz"
      end
      stub_repology_lookup

      expect(matcher.identify(f).identifiable?).to be false
    end
  end

  describe "#build_osv_queries" do
    def pkg(ecosystem:, name:, version:, purl:)
      Homebrew::Vulns::Identify::RegistryPackage.new(ecosystem:, name:, version:, purl:)
    end

    it "emits versionless GIT/registry/distro queries with subject_version carried on the evidence" do
      identity = Homebrew::Vulns::Match::Identity.new(
        git_repo:          "https://github.com/psf/requests",
        git_tag:           "v2.31.0",
        primary_package:   pkg(ecosystem: "PyPI", name: "requests", version: "2.31.0",
                               purl: "pkg:pypi/requests@2.31.0"),
        resource_packages: { "certifi" => pkg(ecosystem: "PyPI", name: "certifi", version: "2024.2.2",
                                              purl: "pkg:pypi/certifi@2024.2.2") },
        distro_packages:   { "Debian" => ["requests"] },
      )

      queries = matcher.build_osv_queries(identity, "2.31.0")

      expect(queries.map(&:first)).to eq [
        { ecosystem: "GIT", name: "https://github.com/psf/requests", version: nil },
        { ecosystem: "PyPI", name: "requests", version: nil },
        { ecosystem: "PyPI", name: "certifi", version: nil },
        { ecosystem: "Debian", name: "requests", version: nil },
      ]
      expect(queries.map { |_, e| [e.strategy, e.ecosystem, e.name, e.subject_version, e.resource] }).to eq [
        [:git, "GIT", "https://github.com/psf/requests", "v2.31.0", nil],
        [:registry, "PyPI", "requests", "2.31.0", nil],
        [:registry, "PyPI", "certifi", "2024.2.2", "certifi"],
        [:distro, "Debian", "requests", nil, nil],
      ]
    end

    it "excludes CPAN packages from OSV queries and omits GIT when no repo derived" do
      identity = Homebrew::Vulns::Match::Identity.new(
        git_repo:          nil,
        git_tag:           "13.55",
        primary_package:   pkg(ecosystem: "CPAN", name: "Image-ExifTool", version: "13.55",
                               purl: "pkg:cpan/EXIFTOOL/Image-ExifTool@13.55"),
        resource_packages: {}, distro_packages: {}
      )

      expect(matcher.build_osv_queries(identity, "13.55")).to eq []
    end
  end

  describe "#range_status" do
    it "keeps an unknown resource range unresolved when the primary package is fixed" do
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "2.0" }] }] },
      ])
      hit = make_hit(v,
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "3.0"),
                     ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: nil, resource: "certifi"))

      expect(matcher.range_status(hit)).to be_nil
    end

    it "uses resolved resource evidence for a fixed override of an unknown aggregate" do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "requests" => { "advisories" => {
          "CVE-1" => { "range_state" => "fixed" },
        } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
          "ranges"  => [{ "type" => "GIT", "events" => [{ "fixed" => "e47e56d" }] }] },
        { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2024.1.0" }] }] },
      ])
      hit = make_hit(v,
                     ev(:git, ecosystem: "GIT", name: "https://github.com/psf/requests",
                              subject_version: "2.31.0", key: "https://github.com/psf/requests"),
                     ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "2024.2.2",
                                   key: "pkg:pypi/certifi@2024.2.2", resource: "certifi"))

      status, evidence = overridden.range_status(hit, formula_name: "requests") ||
                         raise("expected the reviewed override to resolve the range")
      expect([status.state, status.fixed_in, evidence.resource, evidence.key])
        .to eq [:fixed, "2024.1.0", "certifi", "pkg:pypi/certifi@2024.2.2"]
    end

    it "returns the registry-entry status when GIT ranges are uncomparable" do
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/jqlang/jq" },
          "ranges"  => [{ "type" => "GIT", "events" => [{ "fixed" => "e47e56d" }] }] },
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2.28.1" }] }] },
      ])
      hit = make_hit(v,
                     ev(:git, ecosystem: "GIT", name: "https://github.com/jqlang/jq",
                              subject_version: "1.8.1"),
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"))

      status, evidence = matcher.range_status(hit)
      expect(status).to have_attributes(state: :fixed, fixed_in: "2.28.1")
      expect(evidence.strategy).to eq :registry
    end

    it "returns nil when the only matching entry has GIT-type ranges" do
      v = vuln("id" => "CVE-2026-32316", "affected" => [
        { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/jqlang/jq" },
          "ranges"  => [{ "type" => "GIT", "events" => [{ "fixed" => "e47e56d" }] }] },
      ])
      hit = make_hit(v, ev(:git, ecosystem: "GIT", name: "https://github.com/jqlang/jq",
                                 subject_version: "1.8.1"))

      expect(matcher.range_status(hit)).to be_nil
    end

    it "evaluates CPANSA constraint strings for :cpansa evidence" do
      adv = Homebrew::Vulns::CPANSec::Advisory.new(id: "CPANSA-X", cves: ["CVE-1"],
                                                   affected_versions: ["<12.24"],
                                                   fixed_versions: [">=12.24"])
      hit = make_hit(vuln("id" => "CVE-1"),
                     ev(:cpansa, ecosystem: "CPAN", name: "Image-ExifTool",
                                 subject_version: "13.55", advisory: adv))

      expect(matcher.range_status(hit)&.first).to have_attributes(state: :fixed, fixed_in: "12.24")
    end

    it "checks a distro-resolved upstream CVE against attached own-identity evidence" do
      v = vuln("id" => "CVE-2015-8863", "affected" => [
        { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/jqlang/jq" },
          "ranges"  => [{ "type"   => "SEMVER",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "1.6" }] }] },
      ])
      hit = make_hit(v,
                     ev(:distro, ecosystem: "Debian", name: "jq"),
                     ev(:distro, ecosystem: "GIT", name: "https://github.com/jqlang/jq",
                                 subject_version: "1.8.1", key: "upstream:..."))

      expect(matcher.range_status(hit)&.first).to have_attributes(state: :fixed, fixed_in: "1.6")
    end

    it "skips evidence with no subject_version" do
      hit = make_hit(vuln("id" => "CVE-1"), ev(:distro, ecosystem: "Debian", name: "jq"))
      expect(matcher.range_status(hit)).to be_nil
    end

    it "checks each evidence against its own source record after dedup merges hits" do
      # CVE record from GIT query: no PyPI affected entry.
      cve = vuln("id" => "CVE-2024-47081", "affected" => [
        { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
          "ranges"  => [{ "type" => "GIT", "events" => [{ "fixed" => "abc123" }] }] },
      ])
      # GHSA record from PyPI query: carries the PyPI range.
      ghsa = vuln("id" => "GHSA-9hjg-9r4m-mvj7", "aliases" => ["CVE-2024-47081"], "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2.32.4" }] }] },
      ])
      merged = matcher.dedup_by_aliases([
        make_hit(cve, ev(:git, ecosystem: "GIT", name: "https://github.com/psf/requests",
                               subject_version: "2.31.0")),
        make_hit(ghsa, ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0")),
      ])

      expect(merged.length).to eq 1
      status, evidence = matcher.range_status(merged.first)
      expect(status).to have_attributes(state: :affected, fixed_in: "2.32.4")
      expect(evidence.source_record.id).to eq "GHSA-9hjg-9r4m-mvj7"
    end

    it "reports :affected when a resource subject is affected even if the primary is :not_applicable" do
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "3.0.0" }, { "fixed" => "3.0.4" }] }] },
        { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2025.1.1" }] }] },
      ])
      hit = make_hit(v,
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"),
                     ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "2024.2.2",
                                   resource: "certifi"))

      status, evidence = matcher.range_status(hit)
      expect(status).to have_attributes(state: :affected, fixed_in: "2025.1.1")
      expect(evidence.resource).to eq "certifi"
    end

    it "reports :affected when a resource is affected even if the primary is :fixed" do
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2.28.1" }] }] },
        { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2025.1.1" }] }] },
      ])
      hit = make_hit(v,
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"),
                     ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "2024.2.2",
                                   resource: "certifi"))

      expect(matcher.range_status(hit)&.first).to have_attributes(state: :affected)
    end

    it "reports :not_applicable only when every comparable subject is not_applicable" do
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "3.0.0" }, { "fixed" => "3.0.4" }] }] },
      ])
      hit = make_hit(v,
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"),
                     ev(:distro, ecosystem: "Debian", name: "requests"))

      expect(matcher.range_status(hit)&.first&.state).to eq :not_applicable
    end
  end

  describe "#hits_from" do
    let(:cpan_sec) do
      Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {
        "No-CVE-Dist" => { "advisories" => [
          { "id"                => "CPANSA-No-CVE-Dist-2020-01", "cves" => [],
            "affected_versions" => ["<1.0"], "fixed_versions" => [">=1.0"],
            "description" => "d", "references" => ["https://x"] },
        ] },
      } })
    end

    context "with strict CPANSA fetching" do
      let(:cpan_sec) do
        Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {
          "Multi" => { "advisories" => [
            { "id" => "CPANSA-Multi-1", "cves" => ["CVE-2022-4988", "CVE-2022-4989"],
              "affected_versions" => ["<1.0"], "fixed_versions" => [">=1.0"] },
          ] },
        } })
      end
      let(:matcher) { described_class.new(repology:, cpan_sec:, strict_upstream: true) }
      let(:identity) do
        Homebrew::Vulns::Match::Identity.new(
          git_repo: nil, git_tag: nil,
          primary_package: Homebrew::Vulns::Identify::RegistryPackage.new(
            ecosystem: "CPAN", name: "Multi", version: "0.9", purl: "pkg:cpan/X/Multi@0.9",
          ),
          resource_packages: {}, distro_packages: {}
        )
      end

      it "reuses CPANSA evidence for each CVE after a cached supplemental 404" do
        fetched = []
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability) do |id|
          fetched << id
          raise Homebrew::Vulns::OSV::NotFoundError, "404"
        end

        results = Array.new(2) do
          matcher.hits_from({}, identity).map do |hit|
            [hit.canonical_id, matcher.range_status(hit)&.first&.state]
          end
        end

        expect([results, fetched]).to eq [
          Array.new(2) { [["CVE-2022-4988", :affected], ["CVE-2022-4989", :affected]] },
          ["CVE-2022-4988", "CVE-2022-4989"],
        ]
      end

      it "keeps a cached CPANSA supplemental 404 strict for direct query results" do
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability)
          .and_raise(Homebrew::Vulns::OSV::NotFoundError, "404")
        matcher.hits_from({}, identity)

        expect { matcher.resolve_upstream({ "CVE-2022-4988" => [ev(:git)] }, identity) }
          .to raise_error(Homebrew::Vulns::OSV::NotFoundError)
      end

      it "does not replace a transient upstream failure with CPANSA evidence" do
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability)
          .and_raise(Homebrew::Vulns::OSV::ApiError, "503")

        expect { matcher.hits_from({}, identity) }.to raise_error(Homebrew::Vulns::OSV::ApiError, "503")
      end
    end

    it "scopes a synthesised fallback to the CVE being handled when OSV lacks it" do
      cpan_sec = Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {
        "Multi" => { "advisories" => [
          { "id" => "CPANSA-Multi-1", "cves" => ["CVE-2022-4988", "CVE-2022-4989"],
            "affected_versions" => ["<1.0"], "fixed_versions" => [">=1.0"] },
        ] },
      } })
      m = described_class.new(repology:, cpan_sec:)
      identity = Homebrew::Vulns::Match::Identity.new(
        git_repo: nil, git_tag: nil,
        primary_package: Homebrew::Vulns::Identify::RegistryPackage.new(
          ecosystem: "CPAN", name: "Multi", version: "0.9", purl: "pkg:cpan/X/Multi@0.9",
        ),
        resource_packages: {}, distro_packages: {}
      )
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2022-4988")
                                                            .and_raise(Homebrew::Vulns::OSV::ApiError, "404")
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2022-4989")
                                                            .and_return({ "id" => "CVE-2022-4989" })

      hits = m.hits_from({}, identity)

      expect(hits.map(&:canonical_id).sort).to eq ["CVE-2022-4988", "CVE-2022-4989"]
    end

    it "builds a hit directly from a CPANSA advisory that has no CVE alias" do
      identity = Homebrew::Vulns::Match::Identity.new(
        git_repo: nil, git_tag: nil,
        primary_package: Homebrew::Vulns::Identify::RegistryPackage.new(
          ecosystem: "CPAN", name: "No-CVE-Dist", version: "0.9", purl: "pkg:cpan/X/No-CVE-Dist@0.9",
        ),
        resource_packages: {}, distro_packages: {}
      )
      expect(Homebrew::Vulns::OSV).not_to receive(:vulnerability)

      hits = matcher.hits_from({}, identity)

      expect(hits.length).to eq 1
      expect(hits.first.vulnerability.id).to eq "CPANSA-No-CVE-Dist-2020-01"
      expect(hits.first.vulnerability.references).to eq [{ "type" => "WEB", "url" => "https://x" }]
      expect(matcher.range_status(hits.first)&.first)
        .to have_attributes(state: :affected, fixed_in: "1.0")
    end
  end

  describe "#dedup_by_aliases" do
    it "coalesces mutually aliased records without a CVE deterministically" do
      ghsa = make_hit(vuln("id" => "GHSA-9ppg-jx86-fqw7", "aliases" => ["MAL-2026-1380"]),
                      ev(:registry, key: "ghsa"))
      malware = make_hit(vuln("id" => "MAL-2026-1380", "aliases" => ["GHSA-9ppg-jx86-fqw7"]),
                         ev(:registry, key: "malware"))

      results = [[ghsa, malware], [malware, ghsa]].map do |hits|
        merged = matcher.dedup_by_aliases(hits)
        hit = merged.fetch(0)
        [merged.length, hit.canonical_id, hit.identifiers.sort, hit.evidence.map(&:key).sort]
      end

      expect(results).to eq Array.new(2, [
        1,
        "GHSA-9ppg-jx86-fqw7",
        ["GHSA-9ppg-jx86-fqw7", "MAL-2026-1380"],
        %w[ghsa malware],
      ])
    end

    it "merges a one-sided alias chain through its intermediate record" do
      hits = [
        make_hit(vuln("id" => "GHSA-a", "aliases" => ["GHSA-b"]), ev(:registry, key: "a")),
        make_hit(vuln("id" => "GHSA-b", "aliases" => ["GHSA-c"]), ev(:registry, key: "b")),
        make_hit(vuln("id" => "GHSA-c"), ev(:registry, key: "c")),
      ]

      merged = matcher.dedup_by_aliases(hits)

      expect(merged.map { |hit| [hit.canonical_id, hit.identifiers, hit.evidence.map(&:key)] })
        .to eq [["GHSA-a", %w[GHSA-a GHSA-b GHSA-c], %w[a b c]]]
    end

    it "picks the same record in either order when a group ties on strategy and canonical id" do
      ghsa = make_hit(vuln("id"       => "GHSA-5v8v-66v8-mwm7",
                           "aliases"  => ["CVE-2020-36846", "CVE-2020-8927"],
                           "summary"  => "brotli buffer overflow",
                           "severity" => [{ "type" => "CVSS_V3", "score" => "..." }]),
                      ev(:registry, key: "ghsa"))
      pysec = make_hit(vuln("id"      => "PYSEC-2020-29",
                            "aliases" => ["CVE-2020-36846", "CVE-2020-8927"],
                            "summary" => "brotli integer overflow"),
                       ev(:registry, key: "pysec"))

      selected = [[ghsa, pysec], [pysec, ghsa]].map do |hits|
        hit = matcher.dedup_by_aliases(hits).fetch(0)
        [hit.canonical_id, hit.vulnerability.id, hit.vulnerability.summary,
         hit.vulnerability.severity_entries, hit.evidence.map(&:key)]
      end

      expect(selected).to eq Array.new(2, [
        "CVE-2020-36846",
        "GHSA-5v8v-66v8-mwm7",
        "brotli buffer overflow",
        [{ "type" => "CVSS_V3", "score" => "..." }],
        %w[ghsa pysec],
      ])
    end

    it "keeps distinct vulnerabilities reached through the same upstream record" do
      upstream = vuln("id" => "DSA-1")
      evidence = Homebrew::Vulns::Match::Evidence.new(strategy: :distro, key: "Debian/pkg",
                                                      source_record: upstream)
      hits = [
        make_hit(vuln("id" => "CVE-2026-1"), evidence),
        make_hit(vuln("id" => "CVE-2026-2"), evidence),
      ]

      expect(matcher.dedup_by_aliases(hits).map(&:canonical_id)).to eq %w[CVE-2026-1 CVE-2026-2]
    end
  end

  describe "#resolve_upstream" do
    let(:identity) do
      Homebrew::Vulns::Match::Identity.new(
        git_repo: "https://github.com/jqlang/jq", git_tag: "1.8.1",
        primary_package: nil, resource_packages: {}, distro_packages: {}
      )
    end

    it "splits a multi-CVE distro advisory into one hit per upstream CVE with own-identity evidence" do
      allow(matcher).to receive(:fetch_vulnerability).with("RHSA-2026:1").and_return(
        vuln("id" => "RHSA-2026:1", "upstream" => ["CVE-2026-0001", "CVE-2026-0002"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2026-0001")
                                                     .and_return(vuln("id" => "CVE-2026-0001"))
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2026-0002")
                                                     .and_return(vuln("id" => "CVE-2026-0002"))

      hits = matcher.resolve_upstream(
        { "RHSA-2026:1" => [ev(:distro, ecosystem: "Red Hat", name: "jq")] }, identity
      )

      expect(hits.map { |h| h.vulnerability.id }.sort).to eq ["CVE-2026-0001", "CVE-2026-0002"]
      expect(hits.first.evidence.map(&:ecosystem)).to include("Red Hat", "GIT")
    end

    it "follows upstream transitively (USN -> UBUNTU-CVE-* -> CVE-*) with cycle protection" do
      allow(matcher).to receive(:fetch_vulnerability).with("USN-8202-1").and_return(
        vuln("id" => "USN-8202-1", "upstream" => ["UBUNTU-CVE-2024-0001"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("UBUNTU-CVE-2024-0001").and_return(
        vuln("id" => "UBUNTU-CVE-2024-0001", "upstream" => ["CVE-2024-0001", "USN-8202-1"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2024-0001")
                                                     .and_return(vuln("id" => "CVE-2024-0001"))

      hits = matcher.resolve_upstream({ "USN-8202-1" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["CVE-2024-0001"]
    end

    it "consults related for bare CVE ids only for ALSA-* records with no upstream" do
      allow(matcher).to receive(:fetch_vulnerability).with("ALSA-1").and_return(
        vuln("id" => "ALSA-1", "related" => ["CVE-2024-0001", "RHSA-2024:1"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2024-0001")
                                                     .and_return(vuln("id" => "CVE-2024-0001"))

      hits = matcher.resolve_upstream({ "ALSA-1" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["CVE-2024-0001"]
    end

    it "does not consult related for a non-ALSA record with no upstream" do
      allow(matcher).to receive(:fetch_vulnerability).with("MGASA-1").and_return(
        vuln("id" => "MGASA-1", "related" => ["CVE-2024-9999"]),
      )
      hits = matcher.resolve_upstream({ "MGASA-1" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["MGASA-1"]
    end

    it "ignores related when upstream is present" do
      allow(matcher).to receive(:fetch_vulnerability).with("DSA-1").and_return(
        vuln("id" => "DSA-1", "upstream" => ["CVE-2024-0001"], "related" => ["CVE-9999-9999"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2024-0001")
                                                     .and_return(vuln("id" => "CVE-2024-0001"))

      hits = matcher.resolve_upstream({ "DSA-1" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["CVE-2024-0001"]
    end

    it "keeps a record whose id/aliases already include a CVE as-is" do
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2024-0001").and_return(
        vuln("id" => "CVE-2024-0001", "upstream" => ["CVE-2024-0099"]),
      )
      hits = matcher.resolve_upstream({ "CVE-2024-0001" => [ev(:git)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["CVE-2024-0001"]
    end

    it "keeps a record with no CVE anywhere as a low-confidence hit rather than dropping it" do
      allow(matcher).to receive(:fetch_vulnerability).with("ALBA-2022:1788").and_return(
        vuln("id" => "ALBA-2022:1788", "upstream" => [], "related" => ["RHBA-2022:1788"]),
      )
      hits = matcher.resolve_upstream({ "ALBA-2022:1788" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["ALBA-2022:1788"]
    end

    it "caches a missing upstream target while retaining the unresolved distro record" do
      strict = described_class.new(repology:, cpan_sec:, strict_upstream: true)
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DSA-1")
                                                            .and_return({ "id"       => "DSA-1",
                                                                          "upstream" => ["CVE-2024-0404"] })
      expect(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0404").once
                                                             .and_raise(Homebrew::Vulns::OSV::NotFoundError, "404")
      hits = Array.new(2) { strict.resolve_upstream({ "DSA-1" => [ev(:distro)] }, identity) }

      expect(hits.map { |rows| rows.map { |hit| [hit.vulnerability.id, hit.evidence.map(&:strategy)] } })
        .to eq [[["DSA-1", [:distro]]], [["DSA-1", [:distro]]]]
      expect { strict.resolve_upstream({ "CVE-2024-0404" => [ev(:git)] }, identity) }
        .to raise_error(Homebrew::Vulns::OSV::NotFoundError)
    end

    it "continues resolving other upstream targets after a missing link" do
      strict = described_class.new(repology:, cpan_sec:, strict_upstream: true)
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DSA-1")
                                                            .and_return({ "id"       => "DSA-1",
                                                                          "upstream" => ["CVE-2024-0404",
                                                                                         "CVE-2024-0001"] })
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0404")
                                                            .and_raise(Homebrew::Vulns::OSV::NotFoundError, "404")
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0001")
                                                            .and_return({ "id" => "CVE-2024-0001" })

      hits = strict.resolve_upstream({ "DSA-1" => [ev(:distro)] }, identity)

      expect(hits.map { |hit| hit.vulnerability.id }).to eq ["CVE-2024-0001"]
    end

    it "keeps a record as-is when its upstream CVE cannot be fetched" do
      allow(matcher).to receive(:fetch_vulnerability).with("DSA-1").and_return(
        vuln("id" => "DSA-1", "upstream" => ["CVE-2024-0404"]),
      )
      allow(matcher).to receive(:fetch_vulnerability).with("CVE-2024-0404").and_return(nil)
      hits = matcher.resolve_upstream({ "DSA-1" => [ev(:distro)] }, identity)
      expect(hits.map { |h| h.vulnerability.id }).to eq ["DSA-1"]
    end
  end

  describe "#each_advisory_batch" do
    context "when isolating upstream failures" do
      let(:requests) do
        formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/psf/requests/archive/refs/tags/v2.31.0.tar.gz"
        end
      end
      let(:bulk) { described_class.new(repology:, cpan_sec:, bulk: true, strict_upstream: true) }
      let(:other) do
        formula("other") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/owner/other/archive/refs/tags/v1.0.tar.gz"
        end
      end

      before do
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) do |queries|
          queries.map { |query| [{ "id" => query[:name].include?("other") ? "CVE-2024-0002" : "DSA-1" }] }
        end
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0002")
                                                              .and_return({ "id" => "CVE-2024-0002" })
      end

      it "holds only dependent formulae when a prefetched record fails" do
        expect(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DSA-1").once
                                                               .and_raise(Homebrew::Vulns::OSV::NotFoundError, "404")
        held = []
        yielded = []
        bulk.each_advisory_batch([requests, other, requests], on_error: lambda { |f, e|
          held << [f.name, e.message]
        }) do |f, hits|
          yielded << [f.name, hits.map(&:canonical_id)]
        end

        expect([held, yielded]).to eq [
          [["requests", "404"], ["requests", "404"]], [["other", ["CVE-2024-0002"]]]
        ]
      end

      it "holds a formula when an upstream link fails after other hits were resolved" do
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DSA-1")
                                                              .and_return({ "id"       => "DSA-1",
                                                                            "upstream" => ["CVE-2024-0002",
                                                                                           "CVE-2024-0003"] })
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0003")
                                                              .and_raise(Homebrew::Vulns::OSV::ApiError, "503")
        held = []
        yielded = []
        bulk.each_advisory_batch([requests, other], on_error: ->(f, _e) { held << f.name }) do |f, hits|
          yielded << [f.name, hits.map(&:canonical_id)]
        end

        expect([held, yielded]).to eq [["requests"], [["other", ["CVE-2024-0002"]]]]
      end

      it "holds a failed query chunk and continues the next chunk" do
        stub_const("Homebrew::Vulns::Match::BULK_CHUNK", 1)
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) do |queries|
          raise Homebrew::Vulns::OSV::ApiError, "503" unless queries.fetch(0)[:name].include?("other")

          [[{ "id" => "CVE-2024-0002" }]]
        end
        held = []
        yielded = []
        bulk.each_advisory_batch([requests, other], on_error: ->(f, _e) { held << f.name }) do |f, hits|
          yielded << [f.name, hits.map(&:canonical_id)]
        end

        expect([held, yielded]).to eq [["requests"], [["other", ["CVE-2024-0002"]]]]
      end
    end

    it "sends every formula's queries through one OSV.query_batch and yields per-formula hits" do
      a = formula("aa") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/owner/aa/archive/refs/tags/v1.0.tar.gz"
      end
      b = formula("bb") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/owner/bb/archive/refs/tags/v2.0.tar.gz"
      end
      bulk = described_class.new(repology:, cpan_sec:, bulk: true)

      expect(Homebrew::Vulns::OSV).to receive(:query_batch).once.with(
        [
          { ecosystem: "GIT", name: "https://github.com/owner/aa", version: nil },
          { ecosystem: "GIT", name: "https://github.com/owner/bb", version: nil },
        ],
      ).and_return([[{ "id" => "CVE-2024-0001" }], []])
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-0001")
                                                            .and_return({ "id" => "CVE-2024-0001" })

      yielded = T.let([], T::Array[[String, T::Array[String]]])
      bulk.each_advisory_batch([a, b]) { |f, hits| yielded << [f.name, hits.map(&:canonical_id)] }

      expect(yielded).to eq [["aa", ["CVE-2024-0001"]], ["bb", []]]
    end

    it "does not identify or query a formula skipped by reviewed overrides" do
      skipped = formula("aa") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/owner/aa/archive/refs/tags/v1.0.tar.gz"
      end
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({ "aa" => { "skip" => true } })
      bulk = described_class.new(repology:, cpan_sec:, overrides:, bulk: true)
      expect(bulk).not_to receive(:identify)
      expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)

      yielded = []
      bulk.each_advisory_batch([skipped]) { |formula, hits| yielded << [formula.name, hits] }

      expect(yielded).to eq [["aa", []]]
    end
  end

  describe "#advisories_for" do
    let(:exiftool) do
      formula("exiftool") do
        T.bind(self, T.class_of(Formula))
        url "https://cpan.metacpan.org/authors/id/E/EX/EXIFTOOL/Image-ExifTool-13.55.tar.gz"
        head "https://github.com/exiftool/exiftool.git"
      end
    end

    before { stub_repology_lookup({ "Debian" => ["libimage-exiftool-perl"] }) }

    it "queries versionlessly, resolves distro upstream to CVEs, and dedups by CVE alias" do
      expect(Homebrew::Vulns::OSV).to receive(:query_batch).with(
        [
          { ecosystem: "GIT", name: "https://github.com/exiftool/exiftool", version: nil },
          { ecosystem: "Debian", name: "libimage-exiftool-perl", version: nil },
        ],
      ).and_return(
        [
          [{ "id" => "CVE-2021-22204" }],
          [{ "id" => "DEBIAN-CVE-2021-22204" }, { "id" => "DSA-4910-1" }],
        ],
      )
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2021-22204").and_return(
        { "id" => "CVE-2021-22204", "aliases" => ["GHSA-xxxx"] },
      )
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DEBIAN-CVE-2021-22204").and_return(
        { "id" => "DEBIAN-CVE-2021-22204", "upstream" => ["CVE-2021-22204"] },
      )
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("DSA-4910-1").and_return(
        { "id" => "DSA-4910-1", "upstream" => ["CVE-2021-22204", "CVE-2021-99999"] },
      )
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2021-99999").and_return(
        { "id" => "CVE-2021-99999" },
      )

      hits = matcher.advisories_for(exiftool)

      expect(hits.map(&:canonical_id).sort).to eq ["CVE-2021-22204", "CVE-2021-99999"]
      merged = hits.to_h { |h| [h.canonical_id, h] }.fetch("CVE-2021-22204")
      expect(merged.strategy).to eq :git
      expect(merged.identifiers).to include("CVE-2021-22204", "GHSA-xxxx")
      expect(merged.evidence.map(&:strategy).uniq.sort).to eq [:cpansa, :distro, :git]
      expect(merged.evidence.find { |e| e.strategy == :cpansa }&.advisory).not_to be_nil
    end

    it "returns [] without hitting OSV when nothing is identifiable" do
      f = formula("mystery") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/mystery-1.0.tar.gz"
      end
      stub_repology_lookup
      expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)

      expect(matcher.advisories_for(f)).to eq []
    end

    it "caches OSV.vulnerability lookups across calls" do
      allow(Homebrew::Vulns::OSV).to receive(:query_batch)
        .and_return([[{ "id" => "CVE-2021-22204" }], []])
      expect(Homebrew::Vulns::OSV).to receive(:vulnerability).once
                                                             .and_return({ "id" => "CVE-2021-22204" })

      matcher.advisories_for(exiftool)
      matcher.advisories_for(exiftool)
    end
  end

  describe "#to_brew_record" do
    let(:requests) do
      formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
        resource "certifi" do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-2024.2.2.tar.gz"
        end
      end
    end
    let(:now) { Time.utc(2026, 7, 27, 12, 0, 0) }

    def registry_hit(affected_events:, subject_version: "2.31.0", resource: nil, name: "requests")
      make_hit(
        vuln("id" => "CVE-2024-1234", "aliases" => ["GHSA-abcd"], "summary" => "s",
             "severity" => [{ "type" => "CVSS_V3", "score" => "..." }],
             "references" => [{ "type" => "ADVISORY", "url" => "https://x" }],
             "affected" => [{ "package" => { "ecosystem" => "PyPI", "name" => name },
                              "ranges"  => [{ "type" => "ECOSYSTEM", "events" => affected_events }] }]),
        ev(:registry, ecosystem: "PyPI", name:, subject_version:,
                      key: "pkg:pypi/#{name}@#{subject_version}", resource:),
      )
    end

    it "emits fixed=pkg_version and fix: bump when the range says the shipped version is not affected" do
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "fixed" => "2.28.1" }])

      record = matcher.to_brew_record(requests, hit, now:)

      expect(record[:id]).to eq "BREW-requests-CVE-2024-1234"
      expect(matcher.record_id(requests, hit))
        .to eq Homebrew::Vulns::OsvExport.record_for(requests, "CVE-2024-1234", now:)[:id]
      expect(record[:upstream]).to eq ["CVE-2024-1234", "GHSA-abcd"]
      expect(record[:severity]).to eq [{ "type" => "CVSS_V3", "score" => "..." }]
      expect(record[:references]).to eq [{ "type" => "ADVISORY", "url" => "https://x" }]
      aff = record[:affected].first
      expect(aff[:package]).to eq(ecosystem: "Homebrew", name: "requests", purl: "pkg:brew/requests")
      expect(aff[:ranges]).to eq [{ type:   "ECOSYSTEM",
                                    events: [{ introduced: "0" }, { fixed: requests.pkg_version.to_s }] }]
      expect(aff[:ecosystem_specific]).to eq(fix: "bump", range_state: "fixed", upstream_fixed_in: "2.28.1")
      expect(record.dig(:database_specific, :source)).to eq "matched"
      expect(record.dig(:database_specific, :strategy)).to eq "registry"
      expect(record.dig(:database_specific, :confidence)).to eq "high"
    end

    it "deduplicates exported evidence after removing internal provenance" do
      records = ["CVE-2024-1234", "GHSA-abcd"].map do |id|
        vulnerability = vuln(
          "id"       => id,
          "aliases"  => [(id == "CVE-2024-1234") ? "GHSA-abcd" : "CVE-2024-1234"],
          "affected" => [{
            "package" => { "ecosystem" => "PyPI", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.28.1" }
            ] }],
          }],
        )
        make_hit(vulnerability, ev(:registry, ecosystem: "PyPI", name: "requests",
                                              subject_version: "2.31.0", key: "pkg:pypi/requests@2.31.0"))
      end
      hit = matcher.dedup_by_aliases(records).fetch(0)

      evidence = matcher.to_brew_record(requests, hit, now:)
                        .dig(:database_specific, :upstream_evidence)
      expect(evidence).to eq [{
        strategy:        :registry,
        ecosystem:       "PyPI",
        name:            "requests",
        subject_version: "2.31.0",
        key:             "pkg:pypi/requests@2.31.0",
      }]
    end

    it "keeps exported evidence for separate resources of the same package" do
      vulnerability = vuln("id" => "CVE-2024-1234")
      evidence = ["first", "second"].map do |resource|
        ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0",
                      key: "pkg:pypi/requests@2.31.0", resource:)
      end
      hit = make_hit(vulnerability, *evidence)

      expect(matcher.to_brew_record(requests, hit, now:)
                    .dig(:database_specific, :upstream_evidence).map { |row| row[:resource] })
        .to eq ["first", "second"]
    end

    it "emits no fixed event and fix: nil when the range says the shipped version is still affected" do
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "fixed" => "2.32.0" }])

      record = matcher.to_brew_record(requests, hit, now:)

      aff = record[:affected].first
      expect(aff[:ranges]).to eq [{ type: "ECOSYSTEM", events: [{ introduced: "0" }] }]
      expect(aff[:ecosystem_specific]).to eq(fix: nil, range_state: "affected", upstream_fixed_in: "2.32.0")
    end

    it "does not report last_affected as an upstream fix version" do
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "last_affected" => "2.0" }])

      record = matcher.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ranges, 0, :events))
        .to eq [{ introduced: "0" }, { fixed: requests.pkg_version.to_s }]
      expect(record.dig(:affected, 0, :ecosystem_specific)).to eq(fix: "bump", range_state: "fixed")
    end

    it "applies a reviewed advisory override before emitting the range state and upstream fix" do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "requests" => { "advisories" => {
          "CVE-2024-1234" => { "range_state" => "affected", "upstream_fixed_in" => nil },
        } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "fixed" => "2.31.0" }])

      record = overridden.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ranges, 0, :events)).to eq [{ introduced: "0" }]
      expect(record.dig(:affected, 0, :ecosystem_specific)).to eq(fix: nil, range_state: "affected")
    end

    it "can supply a reviewed upstream fix after a last_affected boundary" do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "requests" => { "advisories" => {
          "CVE-2024-1234" => { "upstream_fixed_in" => "2.1" },
        } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "last_affected" => "2.0" }])

      record = overridden.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ecosystem_specific, :upstream_fixed_in)).to eq "2.1"
      expect(overridden.range_status(hit, formula_name: "other")&.first)
        .to have_attributes(state: :fixed, fixed_in: nil)
    end

    it "emits fix: nil and demotes confidence when no comparable range exists (GIT-only)" do
      hit = make_hit(
        vuln("id" => "CVE-2026-32316", "affected" => [
          { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/jqlang/jq" },
            "ranges"  => [{ "type" => "GIT", "events" => [{ "fixed" => "e47e56d" }] }] },
        ]),
        ev(:git, ecosystem: "GIT", name: "https://github.com/jqlang/jq", subject_version: "1.8.1"),
      )

      record = matcher.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ranges, 0, :events)).to eq [{ introduced: "0" }]
      expect(record.dig(:affected, 0, :ecosystem_specific)).to eq(fix: nil)
      expect(record.dig(:database_specific, :confidence)).to eq "medium"
    end

    it "records not_applicable and does not emit fixed for a version below every introduced" do
      hit = registry_hit(affected_events: [{ "introduced" => "3.0.0" }, { "fixed" => "3.0.4" }])

      record = matcher.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ranges, 0, :events)).to eq [{ introduced: "0" }]
      expect(record.dig(:affected, 0, :ecosystem_specific)).to eq(fix: nil, range_state: "not_applicable")
    end

    it "prefers an explicit first_fixed over the derived value" do
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "fixed" => "2.28.1" }])

      record = matcher.to_brew_record(requests, hit, first_fixed: "2.28.1_1", now:)

      expect(record.dig(:affected, 0, :ranges, 0, :events)).to eq [{ introduced: "0" }, { fixed: "2.28.1_1" }]
    end

    it "records resource name and purl and evaluates against the resource's pinned version" do
      hit = registry_hit(affected_events: [{ "introduced" => "0" }, { "fixed" => "2024.2.2" }],
                         subject_version: "2024.2.2", resource: "certifi", name: "certifi")

      record = matcher.to_brew_record(requests, hit, now:)

      expect(record.dig(:affected, 0, :ecosystem_specific))
        .to eq(fix: "bump", range_state: "fixed", upstream_fixed_in: "2024.2.2",
               resource: "certifi", resource_purl: "pkg:pypi/certifi@2024.2.2")
      expect(record.dig(:affected, 0, :ranges, 0, :events).last).to eq(fixed: requests.pkg_version.to_s)
    end
  end

  describe "CPANSA prerelease subjects" do
    let(:matcher) do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "cpan-example" => { "registry_package" => { "ecosystem" => "CPAN", "name" => "Example" } },
      })
      described_class.new(repology:, cpan_sec:, overrides:)
    end
    let(:cpan_formula) do
      formula("cpan-example") do
        T.bind(self, T.class_of(Formula))
        url "https://example.test/example-1.2.3-1.tar.gz"
        version "1.2.3-1"
      end
    end
    let(:hit) do
      advisory = Homebrew::Vulns::CPANSec::Advisory.new(
        id: "CPANSA-Example", cves: ["CVE-2026-1234"],
        affected_versions: ["<2.0"], fixed_versions: [">=2.0"]
      )
      make_hit(
        vuln("id" => "CVE-2026-1234", "affected" => [
          { "package" => { "ecosystem" => "CPAN", "name" => "Example" },
            "ranges"  => [{ "type"   => "SEMVER",
                            "events" => [{ "introduced" => "1.2.3" }, { "fixed" => "2.0" }] }] },
        ]),
        ev(:cpansa, ecosystem: "CPAN", name: "Example", subject_version: "1.2.3-1", advisory:),
      )
    end

    it "uses CPANSA constraints for a current subject at an OSV prerelease boundary" do
      expect(matcher.range_status(hit)&.first).to have_attributes(state: :affected, fixed_in: "2.0")
    end

    it "keeps CPANSA history comparable at an OSV prerelease boundary" do
      expect(matcher.aggregate_state_at(cpan_formula, hit)).to eq :affected
    end

    it "still holds independently ambiguous OSV evidence alongside CPANSA" do
      mixed = make_hit(hit.vulnerability, *hit.evidence,
                       ev(:distro, ecosystem: "CPAN", name: "Example", subject_version: "1.2.3-1"))

      expect([matcher.range_status(mixed), matcher.aggregate_state_at(cpan_formula, mixed)]).to eq [nil, nil]
    end

    it "keeps CPANSA reconciliation comparable at an OSV prerelease boundary" do
      expect(matcher.reconciliation_observation(cpan_formula, hit)).to have_attributes(state: :affected, reasons: [])
    end
  end

  describe "prerelease reconciliation" do
    def prerelease_formula(version)
      formula("openclaw-cli") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/openclaw/-/openclaw-#{version}.tgz"
        resource "dependency" do
          url "https://registry.npmjs.org/dependency/-/dependency-#{version}.tgz"
        end
      end
    end

    def prerelease_hit(introduced: "2026.2.22", fixed: "2026.2.23", resource: nil, type: "SEMVER",
                       subject_version: "2026.2.23")
      name = resource || "openclaw"
      make_hit(
        vuln("id" => "CVE-2026-22217", "affected" => [
          { "package" => { "ecosystem" => "npm", "name" => name },
            "ranges"  => [{ "type" => type, "events" => [
              { "introduced" => introduced }, { "fixed" => fixed }
            ] }] },
        ]),
        ev(:registry, ecosystem: "npm", name:, subject_version:, resource:),
      )
    end

    it "emits a review lead for an ambiguous current primary version" do
      current = prerelease_formula("2026.2.22-2")
      hit = prerelease_hit(subject_version: "2026.2.22-2")
      record = matcher.to_brew_record(current, hit)

      expect([record.dig(:affected, 0, :ecosystem_specific),
              record.dig(:affected, 0, :ranges, 0, :events),
              record.dig(:database_specific, :confidence), record.dig(:database_specific, :review_reason)])
        .to eq [{ fix: nil }, [{ introduced: "0" }], "medium", "prerelease_boundary"]
    end

    it "holds an ambiguous current resource even when another subject is affected" do
      affected = prerelease_hit(introduced: "0", subject_version: "2026.2.22")
      ambiguous = prerelease_hit(resource: "dependency", subject_version: "2026.2.22-2")
      hit = make_hit(affected.vulnerability, *(affected.evidence + ambiguous.evidence))

      expect(matcher.range_status(hit)).to be_nil
    end

    it "checks an ambiguous current version against its own alias source record" do
      fixed = prerelease_hit(introduced: "0", fixed: "2026.2.21", subject_version: "2026.2.22-2")
      ambiguous = prerelease_hit(subject_version: "2026.2.22-2")
      hit = make_hit(fixed.vulnerability, *(fixed.evidence + ambiguous.evidence))

      expect(matcher.range_status(hit)).to be_nil
    end

    it "uses a reviewed state to resolve an ambiguous current version" do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "openclaw-cli" => { "advisories" => { "CVE-2026-22217" => { "range_state" => "fixed" } } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)

      record = overridden.to_brew_record(prerelease_formula("2026.2.22-2"),
                                         prerelease_hit(subject_version: "2026.2.22-2"))
      expect([record.dig(:affected, 0, :ecosystem_specific, :range_state),
              record.dig(:database_specific, :review_reason)]).to eq ["fixed", nil]
    end

    it "resolves current resource ambiguity through an alias state override" do
      hit = prerelease_hit(resource: "dependency", subject_version: "2026.2.22-2")
      allow(hit).to receive(:identifiers).and_return(["CVE-2026-22217", "GHSA-reviewed"])
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "openclaw-cli" => { "advisories" => { "GHSA-reviewed" => { "range_state" => "affected" } } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)

      expect(overridden.range_status(hit, formula_name: "openclaw-cli")&.first&.state).to eq :affected
    end

    it "keeps a threshold-only override from resolving current prerelease ambiguity" do
      overrides = Homebrew::Vulns::AdvisoryOverrides.new({
        "openclaw-cli" => { "advisories" => { "CVE-2026-22217" => { "upstream_fixed_in" => "2026.2.23" } } },
      })
      overridden = described_class.new(repology:, cpan_sec:, overrides:)

      expect(overridden.range_status(prerelease_hit(subject_version: "2026.2.22-2"), formula_name: "openclaw-cli"))
        .to be_nil
    end

    it "keeps a current prerelease below the introduced version not applicable" do
      expect(matcher.range_status(prerelease_hit(subject_version: "2026.2.21-2"))&.first&.state)
        .to eq :not_applicable
    end

    it "keeps a current prerelease affected when both interpretations agree" do
      expect(matcher.range_status(prerelease_hit(subject_version: "2026.2.22-2", introduced: "0"))&.first&.state)
        .to eq :affected
    end

    it "does not treat current build metadata as a prerelease" do
      expect(matcher.range_status(prerelease_hit(subject_version: "2026.2.22+build-2"))&.first&.state)
        .to eq :affected
    end

    it "keeps the current ecosystem-specific decision" do
      expect(matcher.range_status(prerelease_hit(subject_version: "2026.2.22-2", type: "ECOSYSTEM"))&.first&.state)
        .to eq :affected
    end

    it "does not declare never affected when a rebuild suffix crosses the introduction" do
      current = prerelease_formula("2026.2.23")
      older = [prerelease_formula("2026.2.22-2"), prerelease_formula("2026.2.21-2")]
      history = instance_double(Homebrew::Vulns::History)
      allow(Homebrew::Vulns::History).to receive(:new).and_return(history)
      allow(history).to receive(:walk).with(current, complete: true) do |&block|
        older.each { |old| block.call(old) }
        nil
      end

      expect(matcher.reconcile_history(current, prerelease_hit))
        .to have_attributes(state: :unresolved, introduced: nil, fixed: nil, reasons: [:prerelease_boundary])
    end

    it "holds daily fixed-history walks at an ambiguous introduction" do
      current = prerelease_formula("2026.2.23")
      history = instance_double(Homebrew::Vulns::History)
      allow(Homebrew::Vulns::History).to receive(:new).and_return(history)
      allow(history).to receive(:walk).with(current).and_yield(prerelease_formula("2026.2.22-2"))

      expect(matcher.first_fixed_version(current, prerelease_hit)).to eq :history_unavailable
    end

    it "holds daily reintroduction history at an ambiguous introduction" do
      current = prerelease_formula("2026.2.22")
      history = instance_double(Homebrew::Vulns::History)
      allow(Homebrew::Vulns::History).to receive(:new).and_return(history)
      allow(history).to receive(:walk).with(current).and_yield(prerelease_formula("2026.2.22-2"))

      expect(matcher.first_reintroduced_version(current, prerelease_hit(subject_version: "2026.2.22")))
        .to eq :history_unavailable
    end

    it "holds daily resource history at an ambiguous fix" do
      current = prerelease_formula("2026.2.23")
      history = instance_double(Homebrew::Vulns::History)
      allow(Homebrew::Vulns::History).to receive(:new).and_return(history)
      allow(history).to receive(:walk).with(current).and_yield(prerelease_formula("2026.2.22-2"))

      expect(matcher.first_fixed_version(current, prerelease_hit(introduced: "0", fixed: "2026.2.22",
                                                                 resource: "dependency")))
        .to eq :history_unavailable
    end

    it "holds ambiguous current subjects even when another subject is affected" do
      current = prerelease_formula("2026.2.22-2")
      ambiguous = prerelease_hit
      affected = prerelease_hit(introduced: "0", resource: "dependency")
      hit = make_hit(ambiguous.vulnerability, *(ambiguous.evidence + affected.evidence))

      expect(matcher.aggregate_state_at(current, hit)).to be_nil
    end

    it "holds a suffix that changes the state at a fixed boundary" do
      hit = prerelease_hit(introduced: "0", fixed: "2026.2.22")
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-2"), hit))
        .to have_attributes(state: :unknown, reasons: [:prerelease_boundary])
    end

    it "checks resource versions as well as primary packages" do
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-2"),
                                                prerelease_hit(resource: "dependency")))
        .to have_attributes(state: :unknown, reasons: [:prerelease_boundary])
    end

    it "also holds alphabetic prereleases at a boundary" do
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-rc.1"), prerelease_hit))
        .to have_attributes(state: :unknown, reasons: [:prerelease_boundary])
    end

    it "allows a prerelease when both interpretations are affected" do
      hit = prerelease_hit(introduced: "0")
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-2"), hit))
        .to have_attributes(state: :affected, reasons: [])
    end

    it "allows a prerelease when both interpretations precede the introduction" do
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.21-2"), prerelease_hit))
        .to have_attributes(state: :not_applicable, reasons: [])
    end

    it "does not mistake a hyphen in build metadata for a prerelease" do
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22+build-2"), prerelease_hit))
        .to have_attributes(state: :affected, reasons: [])
    end

    it "does not apply semver assumptions to ecosystem ranges" do
      hit = prerelease_hit(type: "ECOSYSTEM", introduced: "0", fixed: "2026.2.22")
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-2"), hit).reasons).to eq []
    end

    it "checks only semver ranges belonging to the matched package" do
      hit = prerelease_hit(type: "ECOSYSTEM", introduced: "0", fixed: "2026.2.22")
      hit.vulnerability.affected << prerelease_hit(resource: "other").vulnerability.affected.fetch(0)
      expect(matcher.reconciliation_observation(prerelease_formula("2026.2.22-2"), hit).reasons).to eq []
    end
  end

  describe "historical boundary walks" do
    let(:requests) do
      formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
      end
    end

    def stub_history(versions_newest_first)
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:path_absent_at_revision?).and_return(false)
      formulae = []
      revs = versions_newest_first.each_with_index.map { |_, i| ["r#{i}", "Formula/r/requests.rb"] }
      allow(fv).to receive(:rev_list) { |_, &b| revs.each { |rev, entry| b.call(rev, entry) } }
      versions_newest_first.each_with_index do |entry, i|
        primary, res, resource_name = Array(entry)
        old = if primary
          formula("requests") do
            T.bind(self, T.class_of(Formula))
            url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-#{primary}.tar.gz"
            if res
              resource resource_name || "certifi" do
                url "https://files.pythonhosted.org/packages/11/22/33/certifi-#{res}.tar.gz"
              end
            end
          end
        end
        allow(fv).to receive(:formula_at_revision).with("r#{i}", anything) do |&b|
          old && b.call(old)
        end
        formulae << old if old
      end
      allow(FormulaVersions).to receive(:new).and_return(fv)
      formulae
    end

    def hit_with_range(*events)
      make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => events }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"),
      )
    end

    def hit_fixed_at(fixed)
      hit_with_range({ "introduced" => "0" }, { "fixed" => fixed })
    end

    describe "#reconcile_history" do
      before do
        allow(Utils).to receive(:popen_read).with(
          "git", "-C", anything, "diff-tree", "--root", "--no-commit-id", "--name-only",
          "--find-renames", "--diff-filter=AR", "-r", anything, safe: true
        ).and_return("Formula/r/requests.rb\n")
      end

      def resource_hit
        make_hit(
          vuln("id" => "CVE-1", "affected" => [
            { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
              "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
                { "introduced" => "0" }, { "fixed" => "1.2" }
              ] }] },
          ]),
          ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.2", resource: "certifi"),
        )
      end

      it "finds both boundaries independently of the ingestion version" do
        stub_history(["2.31.0", "2.30.0", "2.28.1", "2.28.0", "2.27.0"])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :range, introduced: "2.27.0", fixed: "2.28.1", reasons: [])
      end

      it "establishes never affected only after a complete history walk" do
        stub_history(["2.31.0", "2.30.0", "2.29.0"])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :never_affected, introduced: nil, fixed: nil, reasons: [])
      end

      it "continues through below-introduced versions to find older affected builds" do
        stub_history(["2.31.0", "2.27.0", "2.29.0"])
        hit = hit_with_range({ "introduced" => "2.28.0" }, { "fixed" => "2.30.0" })

        expect(matcher.reconcile_history(requests, hit))
          .to have_attributes(state: :range, introduced: "2.29.0", fixed: "2.31.0", reasons: [])
      end

      it "leaves unreadable history unresolved even after finding a fix" do
        stub_history(["2.31.0", "2.28.1", "2.28.0", nil])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, introduced: nil, fixed: nil, reasons: [:history_unavailable])
      end

      it "holds unreadable history at every position, including a possible reintroduction or never-affected result" do
        histories = {
          "before the first affected build"        => ["2.31.0", "2.28.1", "2.28.0", nil, "2.20.0"],
          "inside the affected span"               => ["2.31.0", "2.28.1", "2.28.0", nil, "2.27.0"],
          "between the affected and fixed builds"  => ["2.31.0", "2.28.1", nil, "2.28.0", "2.27.0"],
          "after an apparent fix"                  => ["2.31.0", nil, "2.28.1", "2.28.0", "2.27.0"],
          "possibly hiding a later reintroduction" => [nil, "2.31.0", "2.28.1", "2.28.0", "2.27.0"],
          "in apparently never-affected history"   => ["2.31.0", "2.30.0", nil, "2.29.0"],
        }
        hit = hit_with_range({ "introduced" => "2.25.0" }, { "fixed" => "2.28.1" })
        results = histories.transform_values do |versions|
          stub_history(versions)
          result = described_class.new(repology:, cpan_sec:).reconcile_history(requests, hit)
          [result.state, result.introduced, result.fixed, result.reasons.include?(:history_unavailable)]
        end

        expect(results).to eq histories.transform_values { [:unresolved, nil, nil, true] }
      end

      it "rejects a range covering an unaffected gap" do
        stub_history([["2.31.0", "1.2"], ["2.30.0", "1.0"], ["2.29.0", "1.2"], ["2.28.0", "1.0"]])

        expect(matcher.reconcile_history(requests, resource_hit))
          .to have_attributes(state: :unresolved, reasons: [:unrepresentable_interval])
      end

      it "rejects affected and unaffected builds sharing a package version" do
        stub_history([["2.31.0", "1.2"], ["2.30.0", "1.2"], ["2.30.0", "1.0"]])

        expect(matcher.reconcile_history(requests, resource_hit))
          .to have_attributes(state: :unresolved, reasons: [:unrepresentable_interval])
      end

      it "does not hide disagreement between upstream aliases" do
        stub_history(["2.31.0", "2.29.0", "2.27.0"])
        first = hit_fixed_at("2.28.1")
        other = vuln("id" => "GHSA-1", "aliases" => ["CVE-1"], "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.30.0" }
            ] }] },
        ])
        hit = make_hit(
          first.vulnerability, *first.evidence,
          ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0").with_source(other)
        )

        expect(matcher.reconcile_history(requests, hit))
          .to have_attributes(state: :unresolved, reasons: [:conflicting_upstream])
      end

      it "does not let an affected subject hide an uncomparable subject" do
        stub_history(["2.31.0", "2.30.0"])
        first = hit_fixed_at("2.32.0")
        hit = make_hit(first.vulnerability, *first.evidence,
                       ev(:git, ecosystem: "GIT", name: "https://example.com/unknown", subject_version: nil))

        expect(matcher.reconcile_history(requests, hit))
          .to have_attributes(state: :unresolved, reasons: [:uncomparable_source])
      end

      it "requires review for an advisory-specific patch at the fix boundary" do
        formulae = stub_history(["2.31.0", "2.28.1", "2.28.0"])
        allow(formulae.fetch(1)).to receive(:serialized_patches)
          .and_return([{ "resolves" => [{ "type" => "security", "id" => "CVE-1" }] }])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, reasons: [:advisory_patch_requires_review])
      end

      it "does not block on patches after the affected interval and fix boundary" do
        formulae = stub_history(["2.31.0", "2.28.1", "2.28.0"])
        allow(formulae.fetch(0)).to receive(:serialized_patches)
          .and_return([{ "resolves" => [{ "type" => "security", "id" => "CVE-1" }] }])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :range, fixed: "2.28.1", reasons: [])
      end

      it "does not block on unattributed or unrelated patches" do
        formulae = stub_history(["2.31.0", "2.28.1", "2.28.0"])
        allow(formulae.fetch(2)).to receive(:serialized_patches).and_return([
          { "url" => "https://example.com/build.patch" },
          { "resolves" => [{ "type" => "security", "id" => "CVE-2" }] },
        ])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :range, fixed: "2.28.1", reasons: [])
      end

      it "checks patches throughout history before declaring never affected" do
        formulae = stub_history(["2.31.0", "2.30.0", "2.29.0"])
        allow(formulae.fetch(2)).to receive(:serialized_patches)
          .and_return([{ "resolves" => [{ "type" => "security", "id" => "CVE-1" }] }])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, reasons: [:advisory_patch_requires_review])
      end

      it "collects patch and interval problems independently" do
        formulae = stub_history([["2.31.0", "1.2"], ["2.30.0", "1.2"], ["2.30.0", "1.0"]])
        allow(formulae.fetch(2)).to receive(:serialized_patches)
          .and_return([{ "resolves" => [{ "type" => "security", "id" => "CVE-1" }] }])

        expect(matcher.reconcile_history(requests, resource_hit).reasons)
          .to contain_exactly(:unrepresentable_interval, :advisory_patch_requires_review)
      end

      it "preserves a reviewed range without walking history" do
        overrides = Homebrew::Vulns::AdvisoryOverrides.new({
          "requests" => { "advisories" => { "CVE-1" => { "preserve_homebrew_ranges" => true } } },
        })
        overridden = described_class.new(repology:, cpan_sec:, overrides:)
        allow(FormulaVersions).to receive(:new).and_raise("Protected history must not be walked")

        expect(overridden.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :preserved, introduced: nil, fixed: nil, reasons: [])
      end

      it "does not apply an upstream version override to Homebrew history" do
        stub_history(["2.31.0", "2.28.1", "2.28.0"])
        overrides = Homebrew::Vulns::AdvisoryOverrides.new({
          "requests" => { "advisories" => { "CVE-1" => { "upstream_fixed_in" => "2.27.0" } } },
        })
        overridden = described_class.new(repology:, cpan_sec:, overrides:)

        expect(overridden.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, reasons: [:upstream_override_requires_review])
      end

      it "can establish an open affected interval" do
        stub_history(["2.31.0", "2.30.0"])

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.32.0")))
          .to have_attributes(state: :range, introduced: "2.30.0", fixed: nil, reasons: [])
      end

      it "requires review when an affected build sorts after the current fixed build" do
        stub_history([["2.31.0", "1.2"], ["3.0.0", "1.0"]])

        expect(matcher.reconcile_history(requests, resource_hit))
          .to have_attributes(state: :unresolved, reasons: [:unrepresentable_interval])
      end

      it "recognises a resource patch referencing an advisory alias through its URL" do
        patched = formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
          resource "certifi" do
            url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.0.tar.gz"
            patch do
              url "https://example.com/CVE-2026-12345.patch"
              sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            end
          end
        end
        first = resource_hit
        alias_record = vuln("id" => "CVE-2026-12345", "aliases" => ["CVE-1"])
        hit = make_hit(alias_record, *first.evidence)

        expect(matcher.reconciliation_observation(patched, hit)).to have_attributes(patched: true)
      end

      it "does not require review merely because a formula uses inreplace" do
        rewritten = formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
          def install
            T.bind(self, Formula)
            inreplace "script.py", "/usr/bin/python3", "python3"
          end
        end
        stub_history(["2.31.0", "2.28.1", "2.28.0"])

        expect(matcher.reconcile_history(rewritten, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :range, fixed: "2.28.1", reasons: [])
      end

      it "leaves a renamed primary package unresolved" do
        formulae = stub_history(["2.31.0", "2.30.0"])
        stable = formulae.fetch(1).stable
        raise "Expected a stable formula" unless stable

        allow(stable).to receive(:url)
          .and_return("https://files.pythonhosted.org/packages/aa/bb/cc/old-requests-2.30.0.tar.gz")

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, introduced: nil, fixed: nil, reasons: [:subject_changed])
      end

      it "leaves a changed primary ecosystem unresolved" do
        formulae = stub_history(["2.31.0", "2.30.0"])
        stable = formulae.fetch(1).stable
        raise "Expected a stable formula" unless stable

        allow(stable).to receive(:url).and_return("https://registry.npmjs.org/requests/-/requests-2.30.0.tgz")

        expect(matcher.reconcile_history(requests, hit_fixed_at("2.28.1")))
          .to have_attributes(state: :unresolved, introduced: nil, fixed: nil, reasons: [:subject_changed])
      end

      it "requires every recovered resource identity to occur in history" do
        stub_history([["2.31.0", "1.3"], ["2.30.0", "1.2"]])
        hit = resource_hit
        missing = ev(:registry, ecosystem: "PyPI", name: "missing", subject_version: "1.2", resource: "missing")
        combined = make_hit(hit.vulnerability, *hit.evidence, missing)

        expect(matcher.reconcile_history(requests, combined, require_resource_presence: true))
          .to have_attributes(state: :unresolved, reasons: [:resource_not_found])
      end

      it "witnesses a renamed resource by its source package rather than its label" do
        stub_history([["2.30.0", "1.2", "renamed"]])

        expect(matcher.reconcile_history(requests, resource_hit, require_resource_presence: true))
          .to have_attributes(state: :never_affected, reasons: [])
      end

      it "does not use a stale stored subject version as a historical verdict" do
        stub_history([["2.30.0", "1.0"], ["2.29.0", "0.9"]])
        hit = resource_hit
        evidence = hit.evidence.fetch(0).to_h.merge(subject_version: "99.0")
        stale = make_hit(hit.vulnerability, Homebrew::Vulns::Match::Evidence.new(**evidence))

        expect(matcher.reconcile_history(requests, stale, require_resource_presence: true))
          .to have_attributes(state: :range, introduced: "2.29.0", fixed: "2.31.0", reasons: [])
      end

      it "holds unreadable history even after witnessing a recovered resource" do
        stub_history([["2.30.0", "1.3"], nil])

        expect(matcher.reconcile_history(requests, resource_hit, require_resource_presence: true))
          .to have_attributes(state: :unresolved, reasons: [:history_unavailable])
      end

      it "still treats an absent resource as unaffected" do
        stub_history(["2.31.0", "2.30.0"])

        expect(matcher.reconcile_history(requests, resource_hit))
          .to have_attributes(state: :never_affected, reasons: [])
      end

      it "does not add an irrelevant patch reason to an unrepresentable interval" do
        formulae = stub_history([
          ["2.31.0", "1.2"], ["2.30.0", "1.2"], ["2.29.0", "1.0"], ["2.28.0", "1.2"], ["2.27.0", "1.0"]
        ])
        allow(formulae.fetch(0)).to receive(:serialized_patches)
          .and_return([{ "resolves" => [{ "type" => "security", "id" => "CVE-1" }] }])

        expect(matcher.reconcile_history(requests, resource_hit).reasons).to eq [:unrepresentable_interval]
      end
    end

    it "returns the pkg_version at the oldest revision still at or past upstream fixed_in" do
      stub_history(["2.31.0", "2.30.0", "2.28.1", "2.28.0", "2.27.0"])
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq "2.28.1"
    end

    describe "#first_introduced_version" do
      it "excludes versions below the upstream introduction from a fixed range" do
        stub_history(["2.31.0", "2.30.0", "2.29.0", "2.28.0"])
        hit = hit_with_range({ "introduced" => "2.29.0" }, { "fixed" => "2.30.0" })

        expect(matcher.first_introduced_version(requests, hit, first_fixed: "2.30.0")).to eq "2.29.0"
      end

      it "derives an introduction for a currently affected range" do
        stub_history(["2.31.0", "2.30.0", "2.29.0"])
        hit = hit_with_range({ "introduced" => "2.30.0" }, { "fixed" => "2.32.0" })

        expect(matcher.first_introduced_version(requests, hit)).to eq "2.30.0"
      end

      it "uses the earliest shipped version when all history is affected" do
        stub_history(["2.31.0", "2.30.0"])

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0"))).to eq "2.30.0"
      end

      it "does not infer an introduction through unreadable history" do
        stub_history(["2.31.0", nil, "2.29.0"])

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0")))
          .to eq :history_unavailable
      end

      it "does not infer an introduction from a shallow repository" do
        allow(requests.tap!).to receive(:shallow?).and_return(true)
        stub_history(["2.31.0"])

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0")))
          .to eq :history_unavailable
      end

      it "does not infer an introduction without git history" do
        stub_history([])

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0")))
          .to eq :history_unavailable
      end

      it "rejects an interval containing a known non-affected version" do
        stub_history(["2.31.0", "2.30.0", "2.29.0", "2.28.0"])
        hit = hit_with_range({ "introduced" => "2.28.0" }, { "fixed" => "2.29.0" },
                             { "introduced" => "2.30.0" }, { "fixed" => "2.32.0" })

        expect(matcher.first_introduced_version(requests, hit)).to eq :history_unavailable
      end

      it "rejects an affected version at the proposed fixed boundary" do
        stub_history(["2.31.0", "2.30.0"])

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0"), first_fixed: "2.31.0"))
          .to eq :history_unavailable
      end

      it "excludes revisions before the affected resource was added" do
        current = formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
          resource("certifi") { url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.0.tar.gz" }
        end
        stub_history([["3.0", "1.0"], ["2.0", "1.0"], ["1.0"]])
        hit = make_hit(
          vuln("id" => "CVE-1", "affected" => [
            { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
              "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }] },
          ]),
          ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.0", resource: "certifi"),
        )

        expect(matcher.first_introduced_version(current, hit)).to eq "2.0"
      end

      it "rejects affected and non-affected builds sharing a pkg_version" do
        stub_history(["2.31.0", "2.30.0", "2.30.0"])
        allow(matcher).to receive(:aggregate_state_at).and_return(:affected, :affected, :affected, :not_applicable)

        expect(matcher.first_introduced_version(requests, hit_fixed_at("2.32.0")))
          .to eq :history_unavailable
      end

      it "does not treat an affected state override as evidence of an affected historical build" do
        stub_history(["2.31.0", "2.30.0", "2.29.0"])
        overrides = Homebrew::Vulns::AdvisoryOverrides.new({
          "requests" => { "advisories" => { "CVE-1" => { "range_state" => "affected" } } },
        })
        overridden = described_class.new(repology:, cpan_sec:, overrides:)

        expect(overridden.first_introduced_version(requests, hit_fixed_at("2.30.0")))
          .to eq :history_unavailable
      end
    end

    def stub_pnpm_history(*formulae)
      fv = instance_double(FormulaVersions, load_error: nil)
      revisions = formulae.each_index.map { |index| ["r#{index}", "Formula/p/pnpm.rb"] }
      allow(fv).to receive(:rev_list) { |_, &block| revisions.each { |revision| block.call(*revision) } }
      formulae.each_with_index do |old, index|
        allow(fv).to receive(:formula_at_revision).with("r#{index}", anything).and_yield(old)
      end
      allow(FormulaVersions).to receive(:new).and_return(fv)
    end

    def pnpm_hit
      make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "npm", "name" => "pnpm" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "11.11.0" }] }] },
        ]),
        ev(:registry, ecosystem: "npm", name: "pnpm", subject_version: "12.3.4"),
      )
    end

    it "uses an explicit registry identity across a source transition in history" do
      overridden = described_class.new(repology:, cpan_sec:, overrides: pnpm_overrides)
      current = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/pnpm/pnpm/archive/refs/tags/v12.3.4.tar.gz"
      end
      previous = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/pnpm/-/pnpm-11.10.0.tgz"
      end
      stub_pnpm_history(current, previous)

      expect(overridden.first_fixed_version(current, pnpm_hit)).to eq "12.3.4"
    end

    it "fails a history walk closed when the declared registry identity conflicts" do
      overridden = described_class.new(repology:, cpan_sec:, overrides: pnpm_overrides)
      current = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/pnpm/pnpm/archive/refs/tags/v12.3.4.tar.gz"
      end
      conflicting = formula("pnpm") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/not-pnpm/-/not-pnpm-11.10.0.tgz"
      end
      stub_pnpm_history(conflicting)

      expect(overridden.first_fixed_version(current, pnpm_hit)).to eq :history_unavailable
    end

    it "honours last_affected inclusivity by re-running the range per revision" do
      stub_history(["2.31.0", "2.1", "2.0", "1.9"])
      hit = hit_with_range({ "introduced" => "0" }, { "last_affected" => "2.0" })
      # 2.0 is the last *affected* version so 2.1 is the first fixed pkg_version.
      expect(matcher.first_fixed_version(requests, hit)).to eq "2.1"
    end

    it "returns :never_affected when Homebrew jumped from below introduced straight past fixed" do
      # Advisory {introduced: 2.0, fixed: 3.0}; Homebrew went 1.0 -> 4.0 and
      # never shipped a 2.x, so no BREW record should be emitted.
      stub_history(["4.0", "1.0"])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-4.0.tar.gz"
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "2.0" }, { "fixed" => "3.0" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "4.0"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq :never_affected
    end

    it "returns :never_affected when the formula was already past fixed at its first revision" do
      stub_history(["2.31.0"])
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq :never_affected
    end

    it "returns :history_unavailable for a shallow formula repository" do
      allow(requests.tap!).to receive(:shallow?).and_return(true)
      stub_history(["2.31.0"])

      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq :history_unavailable
    end

    it "does not derive a reintroduction from a shallow formula repository" do
      allow(requests.tap!).to receive(:shallow?).and_return(true)
      stub_history(["2.31.0", "2.30.0"])
      allow(matcher).to receive(:aggregate_state_at).and_return(:affected, :fixed)

      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :history_unavailable
    end

    it "returns :history_unavailable when the formula has no git history" do
      stub_history([])

      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq :history_unavailable
    end

    it "keeps Git history uncheckable across repository URL changes" do
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://github.com/neworg/requests/archive/refs/tags/2.0.tar.gz"
      end
      historical = [
        formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/oldorg/requests/archive/refs/tags/1.1.tar.gz"
        end,
        formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/oldorg/requests/archive/refs/tags/1.0.tar.gz"
        end,
      ]
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:rev_list) do |_, &block|
        historical.each_index { |index| block.call("r#{index}", "Formula/r/requests.rb") }
      end
      historical.each_with_index do |old, index|
        allow(fv).to receive(:formula_at_revision).with("r#{index}", anything).and_yield(old)
      end
      allow(FormulaVersions).to receive(:new).and_return(fv)
      git_hit = lambda do |fixed|
        make_hit(
          vuln("id" => "CVE-1", "affected" => [
            { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/neworg/requests" },
              "ranges"  => [{ "type"   => "ECOSYSTEM",
                              "events" => [{ "introduced" => "0" }, { "fixed" => fixed }] }] },
          ]),
          ev(:git, ecosystem: "GIT", name: "https://github.com/neworg/requests", subject_version: "2.0"),
        )
      end

      expect([
        matcher.first_fixed_version(current, git_hit.call("1.1")),
        matcher.first_reintroduced_version(current, git_hit.call("3.0")),
      ]).to eq [:history_unavailable, :history_unavailable]
    end

    it "returns :never_affected when a fixed resource was absent from earlier formula revisions" do
      stub_history([["2.18.0", "1.2.0"], ["2.17.0", nil]])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.18.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.2.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.0.8" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.2.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq :never_affected
    end

    it "continues past a resource-absence gap to find an older affected revision" do
      stub_history([["3.0", "1.2.0"], ["2.0", nil], ["1.0", "1.0.7"]])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.2.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.0.8" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.2.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq "2.0"
    end

    it "returns :history_unavailable when an older revision after a resource-absence gap cannot be loaded" do
      stub_history([["3.0", "1.2.0"], ["2.0", nil], nil])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.2.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.0.8" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.2.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq :history_unavailable
    end

    it "returns a verified boundary before reaching an older unloadable revision" do
      stub_history(["2.31.0", "2.28.1", "2.28.0", nil])
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq "2.28.1"
    end

    it "follows a resource package across historical resource-label changes" do
      stub_history([["3.0", "101.0", "certifi"], ["2.0", "100.0", "certifi-python"],
                    ["1.0", "99.0", "certifi-python"]])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-101.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "100.0" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "101.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq "2.0"
    end

    it "does not inherit the formula version when a verified package URL has no version" do
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-2.0.tar.gz"
        end
      end
      historical = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-.tar.gz"
        end
      end
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
      allow(fv).to receive(:formula_at_revision).with("r0", anything).and_yield(historical)
      allow(FormulaVersions).to receive(:new).and_return(fv)
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.5" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "2.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq :history_unavailable
    end

    it "does not inherit package identity from a matching resource label" do
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-2.0.tar.gz"
        end
      end
      historical = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.0.tar.gz"
        resource("certifi") do
          url "https://example.com/certifi-1.0.tar.gz"
        end
      end
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
      allow(fv).to receive(:formula_at_revision).with("r0", anything).and_yield(historical)
      allow(FormulaVersions).to receive(:new).and_return(fv)
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.5" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "2.0", resource: "certifi"),
      )

      expect(matcher.first_fixed_version(current, hit)).to eq :history_unavailable
    end

    it "keeps versionless (distro) evidence uncheckable at historical revisions too" do
      stub_history(["2.31.0", "2.30.0", "2.28.1", "2.28.0"])
      # A distro record whose Debian range would spuriously match our formula
      # version if it were compared: ensure it stays skipped in the walk.
      distro_record = vuln("id" => "DEBIAN-CVE-1", "affected" => [
        { "package" => { "ecosystem" => "Debian", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "999+deb12u1" }] }] },
      ])
      registry_record = vuln("id" => "GHSA-x", "aliases" => ["CVE-1"], "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => "2.28.1" }] }] },
      ])
      hit = matcher.dedup_by_aliases([
        make_hit(registry_record,
                 ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0")),
        make_hit(distro_record,
                 ev(:distro, ecosystem: "Debian", name: "requests", subject_version: nil)),
      ]).first

      expect(matcher.first_fixed_version(requests, hit)).to eq "2.28.1"
    end

    it "aggregates every subject per revision so a fixed primary does not mask a later-fixed resource" do
      # Primary requests fixed upstream in 2.0; resource certifi fixed upstream in 100.0.
      # History (formula pkg_version => [primary, certifi]): the resource crossed its
      # threshold at formula 3.0; the primary crossed at 2.0. Aggregate is only :fixed
      # from 3.0 onward.
      stub_history([["4.0", "101.0"], ["3.0", "100.0"], ["2.5", "99.0"], ["2.0", "98.0"], ["1.0", "97.0"]])
      v = vuln("id" => "CVE-1", "affected" => [
        { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "2.0" }] }] },
        { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "100.0" }] }] },
      ])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-4.0.tar.gz"
        resource("certifi") { url "https://files.pythonhosted.org/packages/11/22/33/certifi-101.0.tar.gz" }
      end
      hit = make_hit(v,
                     ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "4.0"),
                     ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "101.0",
                                   resource: "certifi"))

      expect(matcher.first_fixed_version(current, hit)).to eq "3.0"
    end

    it "returns :history_unavailable when a revision cannot be loaded" do
      stub_history(["2.31.0", "2.30.0", nil, "2.28.0"])
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq :history_unavailable
    end

    it "returns nil when the current version is still affected" do
      expect(FormulaVersions).not_to receive(:new)
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.32.0"))).to be_nil
    end

    it "returns nil when there is no comparable range" do
      hit = make_hit(vuln("id" => "CVE-1"), ev(:distro, ecosystem: "Debian", name: "requests"))
      expect(matcher.first_fixed_version(requests, hit)).to be_nil
    end

    it "fails closed when a descending reintroduction would cover a known fixed version" do
      stub_history(["2.31.0", "2.32.0", "2.30.0"])
      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :not_reintroduced
    end

    it "uses the lowest representable version when the affected history moves backwards" do
      stub_history([["3.0", "1.0"], ["4.0", "1.0"], ["2.0", "2.0"]])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.5" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.0", resource: "certifi"),
      )

      expect(matcher.first_reintroduced_version(current, hit)).to eq "3.0"
    end

    it "finds the formula boundary when a bundled resource becomes affected again" do
      stub_history([["4.0", "1.0"], ["3.0", "1.0"], ["2.0", "1.2"], ["1.0", "0.9"]])
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-4.0.tar.gz"
        resource("certifi") do
          url "https://files.pythonhosted.org/packages/11/22/33/certifi-1.0.tar.gz"
        end
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "1.1" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "certifi", subject_version: "1.0", resource: "certifi"),
      )

      expect(matcher.first_reintroduced_version(current, hit)).to eq "3.0"
    end

    it "treats a historical primary-package identity change as absence" do
      current = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/newpkg-1.0.tar.gz"
        revision 1
      end
      previous = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/oldpkg-1.0.tar.gz"
      end
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:rev_list) { |_, &b| b.call("r0", "Formula/r/requests.rb") }
      allow(fv).to receive(:formula_at_revision).with("r0", anything).and_yield(previous)
      allow(FormulaVersions).to receive(:new).and_return(fv)
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "newpkg" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "2.0" }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "newpkg", subject_version: "1.0"),
      )

      expect(matcher.first_reintroduced_version(current, hit)).to eq "1.0_1"
    end

    it "keeps an unidentifiable historical primary package uncheckable" do
      previous = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://example.test/downloads/requests-2.30.0.tar.gz"
      end
      fv = instance_double(FormulaVersions, load_error: nil)
      allow(fv).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
      allow(fv).to receive(:formula_at_revision).with("r0", anything).and_yield(previous)
      allow(FormulaVersions).to receive(:new).and_return(fv)

      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :history_unavailable
      expect(matcher.first_fixed_version(requests, hit_fixed_at("2.28.1"))).to eq :history_unavailable
    end

    it "does not let fixed evidence mask another uncheckable historical subject" do
      previous = formula("requests") do
        T.bind(self, T.class_of(Formula))
        url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.30.0.tar.gz"
      end
      hit = make_hit(
        vuln("id" => "CVE-1", "affected" => [
          { "package" => { "ecosystem" => "PyPI", "name" => "requests" },
            "ranges"  => [{ "type"   => "ECOSYSTEM",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "2.28.1" }] }] },
          { "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
            "ranges"  => [{ "type"   => "GIT",
                            "events" => [{ "introduced" => "0" }, { "fixed" => "f" * 40 }] }] },
        ]),
        ev(:registry, ecosystem: "PyPI", name: "requests", subject_version: "2.31.0"),
        ev(:git, ecosystem: "GIT", name: "https://github.com/psf/requests", subject_version: "e" * 40),
      )

      expect(matcher.aggregate_state_at(previous, hit)).to be_nil
    end

    it "does not invent a boundary when a historical revision cannot be loaded" do
      stub_history([nil])
      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :history_unavailable
    end

    it "does not invent a boundary when a historical revision cannot be compared" do
      stub_history(["2.30.0"])
      allow(matcher).to receive(:aggregate_state_at).and_return(nil)
      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :history_unavailable
    end

    it "does not invent a reintroduction when every historical revision is affected" do
      stub_history(["2.31.0", "2.30.0"])
      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.32.0"))).to eq :not_reintroduced
    end

    it "does not walk reintroduction history when the current version is fixed" do
      expect(FormulaVersions).not_to receive(:new)
      expect(matcher.first_reintroduced_version(requests, hit_fixed_at("2.28.1"))).to be_nil
    end
  end

  describe Homebrew::Vulns::Match::Hit do
    it "sorts evidence by descending strategy precision and reports the highest as #strategy" do
      hit = make_hit(vuln("id" => "CVE-1"), ev(:distro), ev(:git), ev(:registry))
      expect(hit.evidence.map(&:strategy)).to eq [:git, :registry, :distro]
      expect(hit.strategy).to eq :git
    end

    it "uses the lowest CVE alias as canonical_id, or the record id when there is none" do
      expect(make_hit(vuln("id" => "GHSA-x", "aliases" => ["CVE-2024-2", "CVE-2024-1"]),
                      ev(:git)).canonical_id).to eq "CVE-2024-1"
      expect(make_hit(vuln("id" => "GHSA-y"), ev(:git)).canonical_id).to eq "GHSA-y"
    end

    it "rejects empty evidence" do
      expect { described_class.new(vulnerability: vuln("id" => "CVE-1"), evidence: []) }
        .to raise_error(ArgumentError)
    end
  end
end
