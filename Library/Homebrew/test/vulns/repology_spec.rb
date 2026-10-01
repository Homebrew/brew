# typed: true
# frozen_string_literal: true

require "vulns/repology"

RSpec.describe Homebrew::Vulns::Repology do
  let(:fixture) { TEST_FIXTURE_DIR/"vulns/repology.json" }
  let(:index) { described_class.from_file(fixture) }

  describe "#initialize" do
    it "raises Error when the top-level value is not a JSON object" do
      expect { described_class.new([]) }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /not a JSON object/)
    end

    it "raises Error when the formulae key is missing" do
      expect { described_class.new({ "meta" => {} }) }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /missing 'formulae' key/)
    end
  end

  describe "#meta and #formulae" do
    it "exposes the meta block and formula names" do
      expect(index.meta["osv_distros"]).to include "Debian"
      expect(index.meta["ambiguous_projects"]).to eq({ "antlr" => ["antlr", "antlr4-cpp-runtime"] })
      expect(index.formulae).to contain_exactly("curl", "libgee", "ack", "postgresql")
    end
  end

  describe "#distro_packages_for" do
    it "returns the ecosystem => srcnames map for a known formula" do
      expect(index.distro_packages_for("curl")).to eq(
        "Alpine" => ["curl"], "Debian" => ["curl"], "FreeBSD" => ["curl"],
        "Ubuntu" => ["curl"], "openSUSE" => ["curl"]
      )
    end

    it "returns multiple candidate srcnames per ecosystem" do
      expect(index.distro_packages_for("ack")).to eq("Ubuntu" => ["ack", "ack-grep"])
    end

    it "falls back to the base name for an @-versioned formula" do
      expect(index.distro_packages_for("postgresql@16"))
        .to eq("Debian" => ["postgresql-17"], "Alpine" => ["postgresql17"])
    end

    it "returns an empty hash for an unknown formula" do
      expect(index.distro_packages_for("no-such-formula")).to eq({})
    end

    it "returns frozen values" do
      result = index.distro_packages_for("libgee")
      expect(result).to be_frozen
      expect(result["Debian"]).to be_frozen
    end

    it "drops malformed entries when coercing" do
      idx = described_class.new({ "formulae" => { "x" => { "Debian" => ["ok"], 123 => ["bad"],
                                                            "Empty" => [] } } })
      expect(idx.distro_packages_for("x")).to eq("Debian" => ["ok"])
    end
  end

  describe ".name_candidates" do
    it "generates deduplicated normalisation variants" do
      expect(described_class.name_candidates("libmatio"))
        .to eq ["libmatio", "matio"]
    end

    it "strips an @-version suffix and applies affix variants to the base" do
      expect(described_class.name_candidates("gnu-complexity@1"))
        .to eq ["gnu-complexity@1", "gnu-complexity", "complexity"]
    end

    it "strips a trailing 2" do
      expect(described_class.name_candidates("qscintilla2")).to eq ["qscintilla2", "qscintilla"]
    end

    it "returns just the name when no variant applies" do
      expect(described_class.name_candidates("curl")).to eq ["curl"]
    end

    it "does not yield an empty candidate for a bare 'lib' name" do
      expect(described_class.name_candidates("lib")).to eq ["lib"]
    end
  end

  describe ".distil" do
    let(:entries) do
      [
        { "repo" => "debian_12", "srcname" => "curl", "status" => "outdated" },
        { "repo" => "debian_13", "srcname" => "curl", "status" => "newest" },
        { "repo" => "alpine_3_17", "srcname" => "old-curl", "status" => "legacy" },
        { "repo" => "alpine_3_22", "srcname" => "curl", "status" => "newest" },
        { "repo" => "freebsd", "srcname" => "ftp/curl", "binname" => "curl", "status" => "newest" },
        { "repo" => "opensuse_games_tumbleweed", "srcname" => "wrong" },
        { "repo" => "scoop", "binname" => "curl" },
      ]
    end

    it "collapses versioned repos, drops legacy, uses binname for FreeBSD, ignores unmapped repos" do
      expect(described_class.distil(entries))
        .to eq("Alpine" => ["curl"], "Debian" => ["curl"], "FreeBSD" => ["curl"])
    end

    it "collects all distinct srcnames per ecosystem, sorted" do
      multi = [
        { "repo" => "ubuntu_22_04", "srcname" => "ack" },
        { "repo" => "ubuntu_18_04", "srcname" => "ack-grep" },
      ]
      expect(described_class.distil(multi)).to eq("Ubuntu" => ["ack", "ack-grep"])
    end

    it "returns an empty hash for no mappable entries" do
      expect(described_class.distil([{ "repo" => "scoop" }])).to eq({})
    end
  end

  describe ".lookup" do
    def project(homebrew:, distros:, status: "newest")
      homebrew.map { |n| { "repo" => "homebrew", "srcname" => n, "status" => status } } +
        distros.map { |repo, n| { "repo" => repo, "srcname" => n } }
    end

    it "tries name candidates until one contains the requested formula in its Homebrew entries" do
      allow(described_class).to receive(:fetch_project).with("libmatio").and_return([])
      allow(described_class).to receive(:fetch_project).with("matio").and_return(
        project(homebrew: ["libmatio"], distros: [["debian_12", "matio"]]),
      )
      expect(described_class.lookup("libmatio")).to eq("Debian" => ["matio"])
    end

    it "rejects a candidate whose Homebrew entries do not include the requested formula" do
      allow(described_class).to receive(:fetch_project).with("libc").and_return([])
      allow(described_class).to receive(:fetch_project).with("c").and_return(
        project(homebrew: ["c"], distros: [["freebsd", "c"]]),
      )
      expect(described_class.lookup("libc")).to eq({})
    end

    it "accepts a candidate that lists the @-stripped base name" do
      allow(described_class).to receive(:fetch_project).with("node@20").and_return([])
      allow(described_class).to receive(:fetch_project).with("node").and_return(
        project(homebrew: ["node", "node@22"], distros: [["debian_12", "nodejs"]]),
      )
      expect(described_class.lookup("node@20")).to eq("Debian" => ["nodejs"])
    end

    it "accepts a project that also lists sibling formulae with a different base name" do
      # Repology groups wget + wget2 under one project; the sibling's distro
      # srcnames come through as extra low-confidence distro queries whose
      # upstream-CVE range check will not match this formula's identity.
      allow(described_class).to receive(:fetch_project).with("wget").and_return(
        project(homebrew: ["wget", "wget2"],
                distros:  [["debian_12", "wget"], ["debian_12", "wget2"]]),
      )
      expect(described_class.lookup("wget")).to eq("Debian" => ["wget", "wget2"])
    end

    it "still rejects a candidate whose Homebrew entries do not include the requested formula at all" do
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo-utils"], distros: [["debian_12", "wrong"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "foo"]]),
      )
      expect(described_class.lookup("libfoo")).to eq("Debian" => ["foo"])
    end

    it "continues past a candidate with no mapped OSV distros" do
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo"], distros: [["scoop", "foo"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return(
        project(homebrew: ["libfoo"], distros: [["alpine_3_22", "foo"]]),
      )
      expect(described_class.lookup("libfoo")).to eq("Alpine" => ["foo"])
    end

    it "resolves two matching candidates by preferred Homebrew status" do
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "libfoo4"]], status: "rolling"),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "libfoo5"]], status: "newest"),
      )
      expect(described_class.lookup("libfoo")).to eq("Debian" => ["libfoo5"])
    end

    it "prefers a sole exact-name contribution over a preferred base-name contribution" do
      allow(described_class).to receive(:fetch_project).with("libfoo@1").and_return(
        [{ "repo" => "homebrew", "srcname" => "libfoo@1", "status" => "rolling" },
         { "repo" => "homebrew", "srcname" => "libfoo", "status" => "newest" },
         { "repo" => "debian_12", "srcname" => "exact" }],
      )
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "base"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return([])
      expect(described_class.lookup("libfoo@1")).to eq("Debian" => ["exact"])
    end

    it "falls back to a resolved base pool when the exact pool is an unresolvable collision" do
      allow(described_class).to receive(:fetch_project).with("libfoo@1").and_return(
        project(homebrew: ["libfoo@1"], distros: [["debian_12", "a"]]),
      )
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo@1"], distros: [["debian_12", "b"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "base"]]),
      )
      expect(described_class.lookup("libfoo@1")).to eq("Debian" => ["base"])
    end

    it "contributes a project listing both exact and base names to both pools" do
      allow(described_class).to receive(:fetch_project).with("libfoo@1").and_return(
        project(homebrew: ["libfoo@1", "libfoo"], distros: [["debian_12", "a"]]),
      )
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo@1"], distros: [["debian_12", "b"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return([])
      # Exact pool: [a/true, b/true] collides. Base pool: [a/true] (from the
      # first project, which also lists `libfoo`) resolves.
      expect(described_class.lookup("libfoo@1")).to eq("Debian" => ["a"])
    end

    it "returns {} when two matching candidates both have preferred status (unresolvable)" do
      allow(described_class).to receive(:fetch_project).with("libfoo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "a"]]),
      )
      allow(described_class).to receive(:fetch_project).with("foo").and_return(
        project(homebrew: ["libfoo"], distros: [["debian_12", "b"]]),
      )
      expect(described_class.lookup("libfoo")).to eq({})
    end

    it "returns an empty hash when no candidate resolves" do
      allow(described_class).to receive(:fetch_project).and_return([])
      expect(described_class.lookup("no-such")).to eq({})
    end

    it "propagates fetch errors rather than treating them as a miss" do
      allow(described_class).to receive(:fetch_project)
        .and_raise(Homebrew::Vulns::CachedFeed::Error, "Repology API request failed")
      expect { described_class.lookup("curl") }.to raise_error(Homebrew::Vulns::CachedFeed::Error)
    end
  end

  describe ".fetch_project" do
    it "returns the entries array from ::Repology.single_package_query" do
      entries = [{ "repo" => "debian_12", "srcname" => "curl" }]
      allow(Repology).to receive(:single_package_query)
        .with("curl", repository: Repology::HOMEBREW_CORE).and_return({ "curl" => entries })
      expect(described_class.fetch_project("curl")).to eq entries
    end

    it "returns [] for a nonexistent project (HTTP 200 with empty array)" do
      allow(Repology).to receive(:single_package_query).and_return({ "no-such" => [] })
      expect(described_class.fetch_project("no-such")).to eq []
    end

    it "raises Error when the underlying query fails (returns nil)" do
      allow(Repology).to receive(:single_package_query).and_return(nil)
      expect { described_class.fetch_project("curl") }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /request for "curl" failed/)
    end

    it "raises Error on an unexpected response shape" do
      allow(Repology).to receive(:single_package_query).and_return({ "curl" => { "oops" => true } })
      expect { described_class.fetch_project("curl") }
        .to raise_error(Homebrew::Vulns::CachedFeed::Error, /unexpected shape/)
    end
  end

  describe ".load" do
    it "reads a fresh cache file without downloading" do
      Dir.mktmpdir do |dir|
        cache = Pathname(dir)
        FileUtils.cp fixture, cache/"repology.json"
        expect(Utils::Curl).not_to receive(:curl_download)
        expect(described_class.load(cache:).formulae).to include "curl"
      end
    end

    it "falls back to a stale cache when the download fails" do
      Dir.mktmpdir do |dir|
        cache = Pathname(dir)
        stale = cache/"repology.json"
        FileUtils.cp fixture, stale
        FileUtils.touch stale, mtime: Time.now - (described_class.default_max_age + 1)
        expect(Utils::Curl).to receive(:curl_download)
          .and_raise(ErrorDuringExecution.new(["curl"], status: 22))
        loaded = T.let(nil, T.nilable(Homebrew::Vulns::Repology))
        expect { loaded = described_class.load(cache:) }
          .to output(/Failed to refresh repology\.json/).to_stderr
        expect(loaded&.formulae).to include "curl"
      end
    end
  end
end
