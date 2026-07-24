# typed: false
# frozen_string_literal: true

require "cmd/vulns"
require "vulns"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Vulns do
  it_behaves_like "parseable arguments"

  describe "#formulae" do
    let(:installed) { instance_double(Formula, full_name: "curl", recursive_dependencies: []) }

    it "scans installed formulae when no arguments are given, never Formula.all" do
      rack = HOMEBREW_CELLAR/"curl"
      allow(Formula).to receive(:racks).and_return([rack])
      allow(Formulary).to receive(:from_rack).with(rack).and_return(installed)
      expect(Formula).not_to receive(:all)
      expect(described_class.new([]).formulae).to eq [installed]
    end

    it "scans named formulae" do
      named = instance_double(Formula, full_name: "act", recursive_dependencies: [])
      allow_any_instance_of(Homebrew::CLI::NamedArgs).to receive(:to_resolved_formulae).and_return([named])
      expect(described_class.new(["act"]).formulae).to eq [named]
    end

    it "scans the union of --brewfile entries and named arguments" do
      require "bundle/brewfile"
      entry = instance_double(Homebrew::Bundle::Dsl::Entry, type: :brew, name: "wget")
      dsl = instance_double(Homebrew::Bundle::Dsl, entries: [entry])
      from_brewfile = instance_double(Formula, full_name: "wget", recursive_dependencies: [])
      named = instance_double(Formula, full_name: "act", recursive_dependencies: [])
      allow(Homebrew::Bundle::Brewfile).to receive(:read).with(file: nil).and_return(dsl)
      allow(Formulary).to receive(:resolve).with("wget").and_return(from_brewfile)
      allow_any_instance_of(Homebrew::CLI::NamedArgs).to receive(:to_resolved_formulae).and_return([named])

      expect(described_class.new(["act", "--brewfile"]).formulae).to contain_exactly(from_brewfile, named)
    end
  end

  it "reads the default Brewfile when --brewfile is passed without a path" do
    require "bundle/brewfile"
    entry = instance_double(Homebrew::Bundle::Dsl::Entry, type: :brew, name: "act")
    dsl = instance_double(Homebrew::Bundle::Dsl, entries: [entry])
    formula = instance_double(Formula, full_name: "act")
    allow(Formulary).to receive(:resolve).with("act").and_return(formula)

    expect(Homebrew::Bundle::Brewfile).to receive(:read).with(file: nil).and_return(dsl)
    expect(described_class.new(["--brewfile"]).formulae).to eq [formula]

    expect(Homebrew::Bundle::Brewfile).to receive(:read).with(file: "Brewfile.dev").and_return(dsl)
    expect(described_class.new(["--brewfile=Brewfile.dev"]).formulae).to eq [formula]
  end

  it "validates --severity before enumerating formulae" do
    cmd = described_class.new(["--severity=urgent"])
    expect(cmd).not_to receive(:formulae)
    expect { cmd.run }.to raise_error(UsageError)
  end

  describe "#run" do
    def stub_scan(findings)
      results = Homebrew::Vulns::Scanner::Results.new(findings:, checked: 1, skipped: 0)
      allow_any_instance_of(Homebrew::Vulns::Scanner).to receive(:scan).and_return(results)
    end

    let(:act) do
      formula("act") do
        url "https://github.com/nektos/act/archive/refs/tags/v0.2.84.tar.gz"
      end
    end

    before do
      allow_any_instance_of(described_class).to receive(:formulae).and_return([act])
    end

    it "rejects an unknown --severity value" do
      expect { described_class.new(["--severity=urgent"]).run }
        .to raise_error(UsageError, /`--severity` must be one of/)
    end

    it "rejects a non-numeric --max-summary value" do
      expect { described_class.new(["--max-summary=lots"]).run }
        .to raise_error(UsageError, /`--max-summary` must be a non-negative integer/)
    end

    it "rejects a negative --max-summary value" do
      expect { described_class.new(["--max-summary=-5"]).run }
        .to raise_error(UsageError, /`--max-summary` must be a non-negative integer/)
    end

    it "validates options before constructing the scanner" do
      expect(Homebrew::Vulns::Scanner).not_to receive(:new)
      expect { described_class.new(["--max-summary=bad", "--json"]).run }.to raise_error(UsageError)
      expect { described_class.new(["--severity=urgent"]).run }.to raise_error(UsageError)
    end

    it "prints text output and does not set Homebrew.failed when nothing is found" do
      stub_scan([])
      expect { described_class.new([]).run }.to output(/No vulnerabilities found/).to_stdout
      expect(Homebrew.failed?).to be false
    end

    it "sets Homebrew.failed when open vulnerabilities are found" do
      stub_scan([Homebrew::Vulns::Scanner::Finding.new(
        name: "act", version: "0.2.84", tag: "v0.2.84", repo_url: "https://github.com/nektos/act",
        open: [Homebrew::Vulns::Vulnerability.new("id" => "CVE-2024-1234")], patched: []
      )])
      expect { described_class.new([]).run }.to output(/CVE-2024-1234/).to_stdout
      expect(Homebrew.failed?).to be true
    end

    it "does not set Homebrew.failed when only patched vulnerabilities exist" do
      stub_scan([Homebrew::Vulns::Scanner::Finding.new(
        name: "act", version: "0.2.84", tag: "v0.2.84", repo_url: "https://github.com/nektos/act",
        open: [], patched: [Homebrew::Vulns::Vulnerability.new("id" => "CVE-2016-2399")]
      )])
      expect { described_class.new([]).run }.to output(/No open vulnerabilities found/).to_stdout
      expect(Homebrew.failed?).to be false
    end

    it "emits JSON with --json" do
      stub_scan([])
      expect { described_class.new(["--json"]).run }.to output("[]\n").to_stdout
    end

    it "warns to stderr and fails when installed versions could not be checked, even with --json" do
      results = Homebrew::Vulns::Scanner::Results.new(
        findings: [], checked: 1, skipped: 0, outdated_without_sbom: ["openssl@3"],
      )
      allow_any_instance_of(Homebrew::Vulns::Scanner).to receive(:scan).and_return(results)

      expect { described_class.new(["--json"]).run }
        .to output("[]\n").to_stdout
        .and output(/openssl@3.*could not be determined.*brew upgrade/m).to_stderr
      expect(Homebrew.failed?).to be true
    end

    it "passes --severity to the scanner" do
      expect(Homebrew::Vulns::Scanner).to receive(:new)
        .with(anything, hash_including(min_severity: :high))
        .and_return(
          instance_double(Homebrew::Vulns::Scanner,
                          scan: Homebrew::Vulns::Scanner::Results.new(findings: [], checked: 0, skipped: 0)),
        )
      described_class.new(["--severity=high", "--json"]).run
    end

    it "passes --no-ignore-patches to the scanner" do
      expect(Homebrew::Vulns::Scanner).to receive(:new)
        .with(anything, hash_including(ignore_patches: false))
        .and_return(
          instance_double(Homebrew::Vulns::Scanner,
                          scan: Homebrew::Vulns::Scanner::Results.new(findings: [], checked: 0, skipped: 0)),
        )
      described_class.new(["--no-ignore-patches", "--json"]).run
    end

    it "passes --fix-available to the scanner" do
      expect(Homebrew::Vulns::Scanner).to receive(:new)
        .with(anything, hash_including(only_fixed: true))
        .and_return(
          instance_double(Homebrew::Vulns::Scanner,
                          scan: Homebrew::Vulns::Scanner::Results.new(findings: [], checked: 0, skipped: 0)),
        )
      described_class.new(["--fix-available", "--json"]).run
    end

    it "passes --no-fix-available to the scanner" do
      expect(Homebrew::Vulns::Scanner).to receive(:new)
        .with(anything, hash_including(except_fixed: true))
        .and_return(
          instance_double(Homebrew::Vulns::Scanner,
                          scan: Homebrew::Vulns::Scanner::Results.new(findings: [], checked: 0, skipped: 0)),
        )
      described_class.new(["--no-fix-available", "--json"]).run
    end

    it "rejects passing both --fix-available and --no-fix-available" do
      expect { described_class.new(["--fix-available", "--no-fix-available"]).run }
        .to raise_error(
          UsageError,
          /only_fixed and except_fixed cannot be both true|conflicts|conflicts with|mutually exclusive/,
        )
    end

    context "with an installed keg from an untrusted tap" do
      let(:trusted_rack) { HOMEBREW_CELLAR/"act" }
      let(:untrusted_rack) { HOMEBREW_CELLAR/"foo" }

      before do
        allow_any_instance_of(described_class).to receive(:formulae).and_call_original
        allow(Formula).to receive(:racks).and_return([trusted_rack, untrusted_rack])
        allow(Formulary).to receive(:from_rack).with(trusted_rack).and_return(act)
        allow(Formulary).to receive(:from_rack).with(untrusted_rack).and_raise(
          Homebrew::UntrustedTapError,
          "Refusing to load formula someone/tap/foo from untrusted tap someone/tap.",
        )
        stub_scan([])
      end

      it "does not pass the untrusted formula to the scanner" do
        expect(Homebrew::Vulns::Scanner).to receive(:new).with([act], anything).and_call_original
        described_class.new(["--json"]).run
      end

      it "reports the skipped keg and fails" do
        expect { described_class.new(["--json"]).run }
          .to output(%r{untrusted tap.*not scanned.*someone/tap/foo.*brew trust}m).to_stderr
        expect(Homebrew.failed?).to be true
      end
    end
  end
end
