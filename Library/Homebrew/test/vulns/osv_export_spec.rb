# typed: false
# frozen_string_literal: true

require "vulns/osv_export"

RSpec.describe Homebrew::Vulns::OsvExport do
  let(:now) { Time.utc(2026, 6, 28, 12, 0, 0) }

  let(:nvi) do
    formula("nvi") do
      T.bind(self, T.class_of(Formula))
      url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6.orig.tar.gz"
      version "1.81.6"
      revision 6
      patch :p0 do
        file "Patches/nvi/patch-common__db.h"
      end
      patch do
        url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6-17.debian.tar.xz"
        sha256 "abc"
        type :backport
        apply "patches/31regex_heap_overflow.patch"
        resolves "CVE-2015-2305"
      end
    end
  end

  let(:libquicktime) do
    formula("libquicktime") do
      T.bind(self, T.class_of(Formula))
      url "https://downloads.sourceforge.net/project/libquicktime/libquicktime-1.2.4.tar.gz"
      revision 5
      patch do
        url "https://deb.debian.org/debian/pool/main/libq/libquicktime/libquicktime_1.2.4-12.debian.tar.xz"
        sha256 "abc"
        resolves "CVE-2016-2399", "CVE-2017-9122"
      end
    end
  end

  describe ".ranges_terminal?" do
    it "accepts every OSV terminal event and rejects open or malformed ranges" do
      %w[fixed last_affected limit].each do |terminal|
        ranges = [{ "events" => [{ "introduced" => "0" }, { terminal => "2.0" }] }]
        expect(described_class.ranges_terminal?(ranges)).to be true
      end

      expect(described_class.ranges_terminal?([{ "events" => [{ "introduced" => "0" }] }])).to be false
      expect(described_class.ranges_terminal?([])).to be false
      expect(described_class.ranges_terminal?([{ "events" => [] }])).to be false
      wildcard = [{ "events" => [{ "introduced" => "1.0" }, { "limit" => "*" }] }]
      expect(described_class.ranges_terminal?(wildcard)).to be false
      expect(described_class.ranges_open?(wildcard)).to be true
    end
  end

  describe ".merge_existing" do
    it "repairs an unreviewed range with a nonzero initial introduction" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "affected" => [{ "ranges" => [{ "type" => "ECOSYSTEM", "events" => [] }] }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "1.0" }, { fixed: "2.0" }] }] }],
        }

        merged = described_class.merge_existing(path, incoming, close_open_ranges: true, initial_introduction: true)

        expect(JSON.parse(JSON.generate(merged))&.dig("affected", 0, "ranges", 0, "events"))
          .to eq([{ "introduced" => "1.0" }, { "fixed" => "2.0" }])
      end
    end

    it "repairs invalid ranges individually without discarding valid reviewed ranges" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "affected" => [{
            "ranges" => [
              { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "1.0" }] },
              { "type" => "ECOSYSTEM", "events" => [] },
            ],
          }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{
            ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "0" }, { fixed: "2.0" }] }],
          }],
        }

        merged = described_class.merge_existing(path, incoming, close_open_ranges: true)
        ranges = JSON.parse(JSON.generate(merged)).dig("affected", 0, "ranges")

        expect(ranges).to eq [
          { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "1.0" }, { "fixed" => "2.0" }] },
          { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "2.0" }] },
        ]
      end
    end

    [false, true].each do |terminal|
      [false, true].each do |fixed|
        it "repairs mixed ranges without reopening reviewed history (terminal: #{terminal}, fixed: #{fixed})" do
          Dir.mktmpdir do |dir|
            path = File.join(dir, "BREW-x-CVE-1.json")
            reviewed = [{ "introduced" => "1.0" }]
            reviewed << { "fixed" => "1.8" } if terminal
            File.write(path, JSON.generate({
              "id"       => "BREW-x-CVE-1",
              "affected" => [{ "ranges" => [
                { "type" => "ECOSYSTEM", "events" => reviewed },
                { "type" => "ECOSYSTEM", "events" => [] },
              ] }],
            }))
            events = [{ introduced: "1.5" }]
            events << { fixed: "2.0" } if fixed
            incoming = {
              id:       "BREW-x-CVE-1",
              affected: [{ ranges: [{ type: "ECOSYSTEM", events: }] }],
            }

            merged = described_class.merge_existing(path, incoming, close_open_ranges:    true,
                                                                    initial_introduction: true)
            reviewed << { "fixed" => "2.0" } if fixed && !terminal

            expect(JSON.parse(JSON.generate(merged))&.dig("affected", 0, "ranges")).to eq [
              { "type" => "ECOSYSTEM", "events" => reviewed },
              { "type" => "ECOSYSTEM", "events" => JSON.parse(JSON.generate(events)) },
            ]
          end
        end
      end
    end

    it "rejects an initial repair whose fixed boundary does not follow a reviewed open range" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "affected" => [{ "ranges" => [
            { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "2.0" }] },
            { "type" => "ECOSYSTEM", "events" => [] },
          ] }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "1.5" }, { fixed: "2.0" }] }] }],
        }

        expect(described_class.merge_existing(path, incoming, close_open_ranges: true, initial_introduction: true))
          .to be_nil
      end
    end

    it "idempotently reopens every kind of terminal reviewed range from an explicit reintroduction" do
      %w[fixed last_affected limit].each do |terminal|
        Dir.mktmpdir do |dir|
          path = File.join(dir, "BREW-x-CVE-1.json")
          File.write(path, JSON.generate({
            "id"       => "BREW-x-CVE-1",
            "affected" => [{
              "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
                { "introduced" => "0" }, { terminal => "1.0" }
              ] }],
              "ecosystem_specific" => { "range_state" => "fixed" },
            }],
          }))
          incoming = lambda do
            {
              id:       "BREW-x-CVE-1",
              affected: [{
                ranges:             [{ type: "ECOSYSTEM", events: [{ introduced: "2.0" }] }],
                ecosystem_specific: { range_state: "affected" },
              }],
            }
          end

          merged = described_class.merge_existing(path, incoming.call, close_open_ranges: true)
          events = [{ "introduced" => "0" }, { terminal => "1.0" }, { "introduced" => "2.0" }]
          expect(JSON.parse(JSON.generate(merged)).dig("affected", 0, "ranges", 0, "events")).to eq events

          File.write(path, JSON.generate(merged))
          merged_again = described_class.merge_existing(path, incoming.call, close_open_ranges: true)
          expect(merged_again).to be_nil
        end
      end
    end

    it "allows a reintroduction at an exclusive limit but not an inclusive boundary" do
      outcomes = %w[fixed last_affected limit].to_h do |terminal|
        ranges = [{ "type" => "ECOSYSTEM", "events" => [
          { "introduced" => "0" }, { terminal => "2.0" }
        ] }]
        [terminal, described_class.reintroduction_follows?(ranges, "2.0")]
      end

      expect(outcomes).to eq("fixed" => false, "last_affected" => false, "limit" => true)
    end

    it "adds Homebrew version events only to ECOSYSTEM ranges" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        git_events = [{ "introduced" => "a" * 40 }, { "fixed" => "b" * 40 }]
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "affected" => [{
            "ranges" => [
              { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "1.0" }] },
              { "type" => "GIT", "events" => git_events },
            ],
          }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "2.0" }] }] }],
        }

        merged = JSON.parse(JSON.generate(
                              described_class.merge_existing(path, incoming, close_open_ranges: true),
                            ))
        expect(merged.dig("affected", 0, "ranges", 0, "events").last).to eq("introduced" => "2.0")
        expect(merged.dig("affected", 0, "ranges", 1, "events")).to eq git_events
      end
    end

    it "rejects a reintroduction that does not follow the reviewed terminal boundary" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        existing = {
          "id"       => "BREW-x-CVE-1",
          "affected" => [{
            "ranges" => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.0" }
            ] }],
          }],
        }
        File.write(path, JSON.generate(existing))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "1.5" }] }] }],
        }

        expect(described_class.merge_existing(path, incoming, close_open_ranges: true)).to be_nil
        expect(JSON.parse(File.read(path))).to eq existing
      end
    end

    it "rejects a fixed boundary that does not follow every open range" do
      outcomes = ["1.5", "2.0"].map do |introduced|
        Dir.mktmpdir do |dir|
          path = File.join(dir, "BREW-x-CVE-1.json")
          existing = {
            "id"       => "BREW-x-CVE-1",
            "affected" => [{
              "ranges" => [
                { "type" => "ECOSYSTEM", "events" => [
                  { "introduced" => "1.0" }, { "limit" => "*" }
                ] },
                { "type" => "ECOSYSTEM", "events" => [{ "introduced" => introduced }] },
              ],
            }],
          }
          File.write(path, JSON.generate(existing))
          incoming = {
            id:       "BREW-x-CVE-1",
            affected: [{ ranges: [{ type: "ECOSYSTEM", events: [
              { introduced: "0" }, { fixed: "1.5" }
            ] }] }],
          }

          merged = described_class.merge_existing(path, incoming, close_open_ranges: true)
          [merged.nil?, JSON.parse(File.read(path)) == existing]
        end
      end

      expect(outcomes).to eq [[true, true], [true, true]]
    end

    it "refreshes metadata while reopening only terminal ranges in a mixed range set" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "summary"  => "stale",
          "upstream" => ["GHSA-a"],
          "affected" => [{
            "ranges" => [
              { "type" => "ECOSYSTEM", "events" => [
                { "introduced" => "0" }, { "fixed" => "1.0" }
              ] },
              { "type" => "ECOSYSTEM", "events" => [
                { "introduced" => "2.0" }, { "limit" => "*" }
              ] },
            ],
          }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          summary:  "fresh",
          upstream: ["GHSA-a", "CVE-1"],
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [{ introduced: "3.0" }] }] }],
        }

        merged = JSON.parse(JSON.generate(
                              described_class.merge_existing(path, incoming, close_open_ranges: true),
                            ))
        expect(merged.values_at("summary", "upstream", "affected")).to eq [
          "fresh",
          ["GHSA-a", "CVE-1"],
          [{ "ranges" => [
            { "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "1.0" }, { "introduced" => "3.0" }
            ] },
            { "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "2.0" }, { "limit" => "*" }
            ] },
          ] }],
        ]
      end
    end

    it "replaces an unbounded wildcard limit when closing an open range" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-x-CVE-1.json")
        File.write(path, JSON.generate({
          "id"       => "BREW-x-CVE-1",
          "affected" => [{
            "ranges" => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "1.0" }, { "limit" => "*" }
            ] }],
          }],
        }))
        incoming = {
          id:       "BREW-x-CVE-1",
          affected: [{ ranges: [{ type: "ECOSYSTEM", events: [
            { introduced: "0" }, { fixed: "2.0" }
          ] }] }],
        }

        merged = described_class.merge_existing(path, incoming, close_open_ranges: true)
        events = JSON.parse(JSON.generate(merged)).dig("affected", 0, "ranges", 0, "events")
        expect(events).to eq([{ "introduced" => "1.0" }, { "fixed" => "2.0" }])
      end
    end
  end

  describe ".record_for" do
    it "builds a minimal record without upstream data" do
      record = described_class.record_for(nvi, "CVE-2015-2305", now:)

      expect(record[:schema_version]).to eq "1.7.3"
      expect(record[:id]).to eq "BREW-nvi-CVE-2015-2305"
      expect(record[:published]).to eq "2026-06-28T12:00:00Z"
      expect(record[:modified]).to eq "2026-06-28T12:00:00Z"
      expect(record[:upstream]).to eq ["CVE-2015-2305"]
      expect(record[:database_specific]).to eq({ source: "generated" })
      expect(record).not_to have_key(:summary)
      expect(record).not_to have_key(:references)
    end

    it "populates affected package and range" do
      affected = described_class.record_for(nvi, "CVE-2015-2305", now:)[:affected].first

      expect(affected[:package][:ecosystem]).to eq "Homebrew"
      expect(affected[:package][:name]).to eq "nvi"
      expect(affected[:package][:purl]).to eq "pkg:brew/nvi"
      expect(affected[:ranges].first[:events]).to eq [{ introduced: "0" }, { fixed: "1.81.6_6" }]
    end

    it "lists only the patches that resolve the given id in ecosystem_specific" do
      eco = described_class.record_for(nvi, "CVE-2015-2305", now:).dig(:affected, 0, :ecosystem_specific)

      expect(eco[:fix]).to eq "patch"
      expect(eco[:patches]).to eq [
        {
          type:  "backport",
          url:   "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6-17.debian.tar.xz",
          apply: ["patches/31regex_heap_overflow.patch"],
        },
      ]
    end

    it "emits file for local patches and drops entries with no locator" do
      f = formula("x") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/x-1.0.tar.gz"
        patch do
          file "Patches/x/fix.patch"
          resolves "CVE-2024-0001"
        end
        patch do
          url "https://example.com/x/fix.patch"
          sha256 "abc"
          resolves "CVE-2024-0001"
        end
      end
      patches = f.serialized_patches + [{ "resolves" => [{ "type" => "security", "id" => "CVE-2024-0001" }] }]

      refs = described_class.record_for(f, "CVE-2024-0001", patches:, now:)
                            .dig(:affected, 0, :ecosystem_specific, :patches)

      expect(refs).to eq [{ file: "Patches/x/fix.patch" }, { url: "https://example.com/x/fix.patch" }]
    end

    it "reads the given patches list rather than the formula's own serialized_patches" do
      f = formula("x") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/x-1.0.tar.gz"
      end
      linux_only = [{ "url"      => "https://example.com/linux.patch",
                      "resolves" => [{ "type" => "security", "id" => "CVE-2024-0003" }] }]

      eco = described_class.record_for(f, "CVE-2024-0003", patches: linux_only, now:)
                           .dig(:affected, 0, :ecosystem_specific)

      expect(eco[:patches]).to eq [{ url: "https://example.com/linux.patch" }]
    end

    it "merges upstream summary, details, aliases, severity and references" do
      upstream = {
        "summary"    => "Integer overflow in regcomp",
        "details"    => "Long description.",
        "aliases"    => ["GHSA-aaaa-bbbb-cccc"],
        "severity"   => [{ "type" => "CVSS_V3", "score" => "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H" }],
        "references" => [{ "type" => "ADVISORY", "url" => "https://bugs.debian.org/778412" }],
      }

      record = described_class.record_for(nvi, "CVE-2015-2305", upstream:, now:)

      expect(record[:summary]).to eq "Integer overflow in regcomp"
      expect(record[:details]).to eq "Long description."
      expect(record[:upstream]).to eq ["CVE-2015-2305", "GHSA-aaaa-bbbb-cccc"]
      expect(record[:severity]).to eq upstream["severity"]
      expect(record[:references]).to eq upstream["references"]
    end

    it "deduplicates references that differ only by percent-encoding, preserving distinct types" do
      upstream = {
        "references" => [
          { "type" => "WEB", "url" => "https://lists.example.org/announce%40lists/msg" },
          { "type" => "WEB", "url" => "https://lists.example.org/announce@lists/msg" },
          { "type" => "REPORT", "url" => "https://bugs.example.org/+bug/1" },
          { "type" => "ADVISORY", "url" => "https://bugs.example.org/+bug/1" },
        ],
      }

      record = described_class.record_for(nvi, "CVE-2015-2305", upstream:, now:)

      expect(record[:references]).to eq [
        { "type" => "WEB", "url" => "https://lists.example.org/announce%40lists/msg" },
        { "type" => "REPORT", "url" => "https://bugs.example.org/+bug/1" },
        { "type" => "ADVISORY", "url" => "https://bugs.example.org/+bug/1" },
      ]
    end

    it "percent-encodes @ in the purl but not the package name" do
      glibc = formula("glibc@2.13") do
        T.bind(self, T.class_of(Formula))
        url "https://ftp.gnu.org/gnu/glibc/glibc-2.13.tar.gz"
        patch do
          url "https://example.com/fix.patch"
          sha256 "abc"
          resolves "CVE-2024-2961"
        end
      end

      affected = described_class.record_for(glibc, "CVE-2024-2961", now:).dig(:affected, 0)

      expect(affected[:package][:purl]).to eq "pkg:brew/glibc%402.13"
      expect(affected[:package][:name]).to eq "glibc@2.13"
    end

    it "percent-encodes + in the purl" do
      libsigcxx = formula("libsigc++") do
        T.bind(self, T.class_of(Formula))
        url "https://download.gnome.org/sources/libsigc++/3.6/libsigc++-3.6.0.tar.xz"
        patch do
          url "https://example.com/fix.patch"
          sha256 "abc"
          resolves "CVE-2024-0002"
        end
      end

      affected = described_class.record_for(libsigcxx, "CVE-2024-0002", now:).dig(:affected, 0)

      expect(affected[:package][:purl]).to eq "pkg:brew/libsigc%2B%2B"
      expect(affected[:package][:name]).to eq "libsigc++"
    end

    it "uses an explicit fixed boundary over the current pkg_version" do
      events = described_class.record_for(nvi, "CVE-2015-2305", fixed: "1.81.6_3", now:)
                              .dig(:affected, 0, :ranges, 0, :events)

      expect(events[1]).to eq({ fixed: "1.81.6_3" })
    end

    it "omits the revision suffix when revision is zero" do
      f = formula("x") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/x-1.0.tar.gz"
        patch do
          url "https://example.com/fix.patch"
          sha256 "abc"
          resolves "CVE-2024-0001"
        end
      end

      events = described_class.record_for(f, "CVE-2024-0001", now:).dig(:affected, 0, :ranges, 0, :events)

      expect(events[1]).to eq({ fixed: "1.0" })
    end
  end

  describe ".run" do
    it "writes one file per (formula, CVE) pair" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})

      Dir.mktmpdir do |dir|
        annotated = [[nvi, nvi.serialized_patches], [libquicktime, libquicktime.serialized_patches]]
        written = described_class.run(annotated, dir, now:)

        expect(written.map { |p| File.basename(p) }.sort).to eq [
          "BREW-libquicktime-CVE-2016-2399.json",
          "BREW-libquicktime-CVE-2017-9122.json",
          "BREW-nvi-CVE-2015-2305.json",
        ]
        written.each do |p|
          record = JSON.parse(File.read(p))
          expect(record["affected"][0]["package"]["ecosystem"]).to eq "Homebrew"
        end
      end
    end

    it "calls first_fixed only for records with no existing file" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})
      calls = []
      first_fixed = lambda { |f, id|
        calls << [f.name, id]
        "1.2.4_2"
      }

      Dir.mktmpdir do |dir|
        File.write("#{dir}/BREW-libquicktime-CVE-2016-2399.json",
                   JSON.generate(described_class.record_for(libquicktime, "CVE-2016-2399", now:)))

        described_class.run([[libquicktime, libquicktime.serialized_patches]], dir, first_fixed:, now:)

        expect(calls).to eq [["libquicktime", "CVE-2017-9122"]]
        record = JSON.parse(File.read("#{dir}/BREW-libquicktime-CVE-2017-9122.json"))
        expect(record["affected"][0]["ranges"][0]["events"][1]).to eq({ "fixed" => "1.2.4_2" })
      end
    end

    it "falls back to pkg_version when first_fixed returns nil" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})

      Dir.mktmpdir do |dir|
        described_class.run([[nvi, nvi.serialized_patches]], dir, first_fixed: ->(_f, _id) {}, now:)

        record = JSON.parse(File.read("#{dir}/BREW-nvi-CVE-2015-2305.json"))
        expect(record["affected"][0]["ranges"][0]["events"][1]).to eq({ "fixed" => "1.81.6_6" })
      end
    end

    it "skips a new record when formula history is unavailable" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})

      Dir.mktmpdir do |dir|
        written = described_class.run(
          [[nvi, nvi.serialized_patches]], dir,
          first_fixed: ->(_f, _id) { :history_unavailable }, now:
        )

        expect([written, Dir.children(dir)]).to eq [[], []]
      end
    end

    it "rejects an unknown first-fixed result" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})

      Dir.mktmpdir do |dir|
        expect do
          described_class.run(
            [[nvi, nvi.serialized_patches]], dir,
            first_fixed: ->(_f, _id) { :future_result }, now:
          )
        end.to raise_error(TypeError, /unexpected first-fixed result: :future_result/)
      end
    end

    it "fetches each upstream vuln id once, even when shared across formulae" do
      shared = [{ "url"      => "https://example.com/fix.patch",
                  "resolves" => [{ "type" => "security", "id" => "CVE-2024-9999" }] }]
      a = formula("a") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/a-1.0.tar.gz"
      end
      b = formula("b") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/b-1.0.tar.gz"
      end

      expect(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-9999").once.and_return({})

      Dir.mktmpdir do |dir|
        written = described_class.run([[a, shared], [b, shared]], dir, now:)
        expect(written.map { |p| File.basename(p) }.sort)
          .to eq ["BREW-a-CVE-2024-9999.json", "BREW-b-CVE-2024-9999.json"]
      end
    end

    context "with an existing record on disk" do
      let(:earlier) { Time.utc(2026, 6, 1, 0, 0, 0) }
      let(:nvi_bumped) do
        formula("nvi") do
          T.bind(self, T.class_of(Formula))
          url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6.orig.tar.gz"
          version "1.81.6"
          revision 7
          patch do
            url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6-17.debian.tar.xz"
            sha256 "abc"
            type :backport
            apply "patches/31regex_heap_overflow.patch"
            resolves "CVE-2015-2305"
          end
        end
      end

      before do
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})
      end

      def seed(dir, formula)
        described_class.run([[formula, formula.serialized_patches]], dir, now: earlier)
      end

      it "preserves the existing fixed boundary and published timestamp when core bumps the version" do
        Dir.mktmpdir do |dir|
          seed(dir, nvi)
          expect(nvi_bumped.pkg_version.to_s).to eq "1.81.6_7"

          described_class.run([[nvi_bumped, nvi_bumped.serialized_patches]], dir, now:)

          record = JSON.parse(File.read("#{dir}/BREW-nvi-CVE-2015-2305.json"))
          expect(record["published"]).to eq "2026-06-01T00:00:00Z"
          expect(record["affected"][0]["ranges"][0]["events"][1]).to eq({ "fixed" => "1.81.6_6" })
        end
      end

      it "does not rewrite when nothing has changed" do
        Dir.mktmpdir do |dir|
          seed(dir, nvi)

          written = described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          expect(written).to eq []
          record = JSON.parse(File.read("#{dir}/BREW-nvi-CVE-2015-2305.json"))
          expect(record["modified"]).to eq "2026-06-01T00:00:00Z"
        end
      end

      it "updates modified when refreshed upstream data differs" do
        Dir.mktmpdir do |dir|
          seed(dir, nvi)
          allow(Homebrew::Vulns::OSV).to receive(:vulnerability)
            .and_return({ "summary" => "New summary" })

          written = described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          expect(written).to eq ["#{dir}/BREW-nvi-CVE-2015-2305.json"]
          record = JSON.parse(File.read(written.first))
          expect(record["summary"]).to eq "New summary"
          expect(record["published"]).to eq "2026-06-01T00:00:00Z"
          expect(record["modified"]).to eq "2026-06-28T12:00:00Z"
        end
      end

      it "leaves an existing enriched record untouched when the upstream fetch fails" do
        Dir.mktmpdir do |dir|
          allow(Homebrew::Vulns::OSV).to receive(:vulnerability)
            .and_return({ "summary" => "Cached summary", "aliases" => ["GHSA-aaaa-bbbb-cccc"] })
          seed(dir, nvi)
          before = File.read("#{dir}/BREW-nvi-CVE-2015-2305.json")
          expect(JSON.parse(before)["summary"]).to eq "Cached summary"

          allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_raise(Homebrew::Vulns::OSV::ApiError)
          written = described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          expect(written).to eq []
          expect(File.read("#{dir}/BREW-nvi-CVE-2015-2305.json")).to eq before
        end
      end

      it "backfills published from an existing modified when the record predates the published field" do
        Dir.mktmpdir do |dir|
          seed(dir, nvi)
          path = "#{dir}/BREW-nvi-CVE-2015-2305.json"
          legacy = JSON.parse(File.read(path)).tap { |h| h.delete("published") }
          File.write(path, "#{JSON.pretty_generate(legacy)}\n")

          described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          record = JSON.parse(File.read(path))
          expect(record["published"]).to eq "2026-06-01T00:00:00Z"
          expect(record["modified"]).to eq "2026-06-28T12:00:00Z"
        end
      end

      it "does not rewrite when the existing file has a different key order" do
        Dir.mktmpdir do |dir|
          seed(dir, nvi)
          path = "#{dir}/BREW-nvi-CVE-2015-2305.json"
          reordered = JSON.parse(File.read(path)).sort.reverse.to_h
          File.write(path, "#{JSON.pretty_generate(reordered)}\n")
          expect(reordered.keys.first).to eq "upstream"

          written = described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          expect(written).to eq []
          expect(JSON.parse(File.read(path))["modified"]).to eq "2026-06-01T00:00:00Z"
        end
      end

      it "leaves other files in the directory untouched" do
        Dir.mktmpdir do |dir|
          curated = "#{dir}/BREW-2026-0001.json"
          File.write(curated, JSON.generate(id: "BREW-2026-0001"))
          orphan = "#{dir}/BREW-gone-CVE-2020-0001.json"
          File.write(orphan, JSON.generate(id:                "BREW-gone-CVE-2020-0001",
                                           database_specific: { source: "generated" }))

          described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

          expect(File.read(curated)).to eq JSON.generate(id: "BREW-2026-0001")
          expect(File.exist?(orphan)).to be true
        end
      end
    end

    it "still writes a record when the upstream fetch fails" do
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_raise(Homebrew::Vulns::OSV::ApiError)

      Dir.mktmpdir do |dir|
        written = described_class.run([[nvi, nvi.serialized_patches]], dir, now:)

        expect(written.size).to eq 1
        record = JSON.parse(File.read(written.first))
        expect(record["upstream"]).to eq ["CVE-2015-2305"]
        expect(record).not_to have_key("summary")
      end
    end
  end
end
