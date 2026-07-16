# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-vulns-advisories"

RSpec.describe Homebrew::DevCmd::GenerateVulnsAdvisories do
  it_behaves_like "parseable arguments"

  it "writes advisories for core formulae with security patch resolves" do
    nvi = formula("nvi") do
      url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6.orig.tar.gz"
      version "1.81.6"
      revision 6
      patch do
        url "https://deb.debian.org/debian/pool/main/n/nvi/nvi_1.81.6-17.debian.tar.xz"
        sha256 "abc"
        resolves "CVE-2015-2305"
      end
    end
    plain = formula("plain") { url "https://example.com/plain-1.0.tar.gz" }
    [nvi, plain].each do |f|
      allow(f).to receive(:to_hash_with_variations)
        .and_return({ "patches" => f.serialized_patches, "variations" => {} })
    end

    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core", formula_names: ["nvi", "plain"])
    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(Formulary).to receive(:enable_factory_cache!)
    allow(Formulary).to receive(:factory).with("nvi").and_return(nvi)
    allow(Formulary).to receive(:factory).with("plain").and_return(plain)
    allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_return({})
    allow(FormulaVersions).to receive(:new).and_return(instance_double(FormulaVersions, rev_list: nil))

    Dir.mktmpdir do |dir|
      out = "#{dir}/advisories"
      described_class.new([out]).run

      files = Dir.children(out).sort
      expect(files).to eq ["BREW-nvi-CVE-2015-2305.json"]

      record = JSON.parse(File.read("#{out}/BREW-nvi-CVE-2015-2305.json"))
      expect(record["affected"][0]["package"]["ecosystem"]).to eq "Homebrew"
      expect(record["affected"][0]["ranges"][0]["events"][1]).to eq({ "fixed" => "1.81.6_6" })
    end
  end

  it "writes nothing with --dry-run" do
    nvi = formula("nvi") do
      url "https://example.com/nvi-1.81.6.tar.gz"
      patch do
        url "https://example.com/fix.patch"
        sha256 "abc"
        resolves "CVE-2015-2305"
      end
    end
    allow(nvi).to receive(:to_hash_with_variations)
      .and_return({ "patches" => nvi.serialized_patches, "variations" => {} })

    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core", formula_names: ["nvi"])
    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(Formulary).to receive(:enable_factory_cache!)
    allow(Formulary).to receive(:factory).with("nvi").and_return(nvi)

    Dir.mktmpdir do |dir|
      out = "#{dir}/nonexistent"
      expect(Homebrew::Vulns::OSV).not_to receive(:vulnerability)
      expect { described_class.new(["--dry-run", out]).run }
        .to output(/^BREW-nvi-CVE-2015-2305$/).to_stdout
      expect(Dir.exist?(out)).to be false
    end
  end

  describe "#all_variation_patches" do
    subject(:cmd) { described_class.new(["out"]) }

    it "unions base patches with every variation's patches, deduplicated" do
      f = instance_double(
        Formula,
        to_hash_with_variations: {
          "patches"    => [{ "url" => "a" }, { "url" => "b" }],
          "variations" => {
            arm64_linux:  { "patches" => [{ "url" => "a" }, { "url" => "linux-only" }] },
            x86_64_linux: { "name" => "irrelevant" },
          },
        },
      )

      expect(cmd.all_variation_patches(f)).to eq [{ "url" => "a" }, { "url" => "b" }, { "url" => "linux-only" }]
    end

    it "returns base patches when there are no variations" do
      f = instance_double(
        Formula,
        to_hash_with_variations: { "patches" => [{ "url" => "a" }], "variations" => {} },
      )

      expect(cmd.all_variation_patches(f)).to eq [{ "url" => "a" }]
    end
  end

  describe "#first_fixed_version" do
    subject(:cmd) { described_class.new(["out"]) }

    let(:current) { formula("x") { url "https://example.com/x-1.2.tar.gz" } }

    def with_history(revisions)
      fv = instance_double(FormulaVersions)
      allow(FormulaVersions).to receive(:new).with(current).and_return(fv)
      allow(fv).to receive(:rev_list).with("HEAD") do |&blk|
        revisions.each_key { |rev| blk.call(rev, "Formula/x/x.rb") }
      end
      allow(fv).to receive(:formula_at_revision) do |rev, _entry, &blk|
        old = revisions.fetch(rev)
        old.nil? ? nil : blk.call(old)
      end
    end

    def old_formula(pkg_version:, resolves_ids: [])
      patches = resolves_ids.map { |id| { "resolves" => [{ "type" => "security", "id" => id }] } }
      instance_double(Formula, pkg_version: PkgVersion.parse(pkg_version), serialized_patches: patches)
    end

    it "returns the pkg_version at the oldest revision where the CVE is resolved" do
      with_history(
        "r3" => old_formula(pkg_version: "1.2_1", resolves_ids: ["CVE-2024-1"]),
        "r2" => old_formula(pkg_version: "1.2", resolves_ids: ["CVE-2024-1"]),
        "r1" => old_formula(pkg_version: "1.1", resolves_ids: []),
        # Trap: if the walk continued past r1 it would wrongly return 1.0.
        "r0" => old_formula(pkg_version: "1.0", resolves_ids: ["CVE-2024-1"]),
      )

      expect(cmd.first_fixed_version(current, "CVE-2024-1")).to eq "1.2"
    end

    it "returns the oldest resolved version when the CVE is resolved in every revision" do
      with_history(
        "r2" => old_formula(pkg_version: "1.1", resolves_ids: ["CVE-2024-1"]),
        "r1" => old_formula(pkg_version: "1.0", resolves_ids: ["CVE-2024-1"]),
      )

      expect(cmd.first_fixed_version(current, "CVE-2024-1")).to eq "1.0"
    end

    it "stops at an unloadable revision and returns the last known resolved version" do
      with_history(
        "r3" => old_formula(pkg_version: "1.2", resolves_ids: ["CVE-2024-1"]),
        "r2" => nil,
        "r1" => old_formula(pkg_version: "1.0", resolves_ids: ["CVE-2024-1"]),
      )

      expect(cmd.first_fixed_version(current, "CVE-2024-1")).to eq "1.2"
    end

    it "returns nil when the CVE is not resolved at the newest revision" do
      with_history(
        "r2" => old_formula(pkg_version: "1.2", resolves_ids: []),
        # Trap: if the walk continued past r2 it would wrongly return 1.0.
        "r1" => old_formula(pkg_version: "1.0", resolves_ids: ["CVE-2024-1"]),
      )

      expect(cmd.first_fixed_version(current, "CVE-2024-1")).to be_nil
    end
  end
end
